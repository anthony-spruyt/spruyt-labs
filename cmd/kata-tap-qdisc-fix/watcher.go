package main

import (
	"context"
	"errors"
	"log/slog"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
)

// fsnotify on /run/netns/ is a latency optimisation, NOT a correctness path.
// Netns files in that directory are created via `mount --bind /proc/<pid>/ns/net`
// by the CNI/runtime, and whether Linux inotify fires IN_CREATE for bind-mount
// targets is kernel-version dependent. The 30-second periodic sweep is the
// authoritative correctness source; fsnotify only shortens the tail.

// ---------- Clock abstraction ----------

// Clock is injected into Watcher so tests can drive virtual time without
// time.Sleep. Production uses realClock; tests use fakeClock.
type Clock interface {
	Now() time.Time
	After(d time.Duration) <-chan time.Time
	NewTicker(d time.Duration) Ticker
}

type Ticker interface {
	C() <-chan time.Time
	Stop()
}

type realClock struct{}

func (realClock) Now() time.Time                         { return time.Now() }
func (realClock) After(d time.Duration) <-chan time.Time { return time.After(d) }
func (realClock) NewTicker(d time.Duration) Ticker       { return &realTicker{t: time.NewTicker(d)} }

type realTicker struct{ t *time.Ticker }

func (r *realTicker) C() <-chan time.Time { return r.t.C }
func (r *realTicker) Stop()               { r.t.Stop() }

// ---------- Watcher types ----------

type QdiscManagerFactory func() QdiscManager

const (
	CircuitBreakerMaxFailures = 10
	CircuitBreakerCooldown    = 10 * time.Minute
	tapNotFoundAttemptsMax    = 30
	enqueueRecoveryTimeout    = 1 * time.Second
)

type retryTrack int

const (
	trackNone retryTrack = iota
	trackTapNotPresent
	trackFailure
)

type workItem struct {
	netnsPath string
	// track+attempt are filled in by scheduleRetry when re-enqueuing.
	// Fresh enqueues from sweep/fsnotify leave these zero.
	track   retryTrack
	attempt int
}

type pathState struct {
	nextEligible        time.Time
	consecutiveFailures int
	tapNotFoundAttempts int
	lastSeen            time.Time
}

type Watcher struct {
	dir           string
	opener        NetnsOpener
	factory       QdiscManagerFactory
	dryRun        bool
	sweepInterval time.Duration
	metrics       *Metrics
	logger        *slog.Logger
	clock         Clock

	retryInitial time.Duration
	retryMax     time.Duration

	workCh chan workItem
	stopCh chan struct{}
	wg     sync.WaitGroup

	mu    sync.Mutex
	state map[string]*pathState
}

func NewWatcher(
	dir string,
	opener NetnsOpener,
	factory QdiscManagerFactory,
	dryRun bool,
	sweepInterval time.Duration,
	metrics *Metrics,
	logger *slog.Logger,
	clock Clock,
) *Watcher {
	if clock == nil {
		clock = realClock{}
	}
	return &Watcher{
		dir:           dir,
		opener:        opener,
		factory:       factory,
		dryRun:        dryRun,
		sweepInterval: sweepInterval,
		metrics:       metrics,
		logger:        logger,
		clock:         clock,
		retryInitial:  250 * time.Millisecond,
		retryMax:      8 * time.Second,
		workCh:        make(chan workItem, 256),
		stopCh:        make(chan struct{}),
		state:         make(map[string]*pathState),
	}
}

// setRetryBackoffForTest overrides retry timings. Unexported: tests in the
// same package can call it; other packages cannot. Never invoked in prod.
func (w *Watcher) setRetryBackoffForTest(initial, max time.Duration) {
	w.retryInitial = initial
	w.retryMax = max
}

// ---------- Start / Stop ----------

func (w *Watcher) Start(ctx context.Context) {
	w.wg.Add(1)
	go w.superviseWorker(ctx)
	w.wg.Add(1)
	go w.sweeper(ctx)
	w.wg.Add(1)
	go w.fsnotifyLoop(ctx)
}

func (w *Watcher) Stop() {
	close(w.stopCh)
	w.wg.Wait()
}

// superviseWorker runs the worker goroutine. If the worker exits while
// neither ctx nor stopCh has signalled, the supervisor increments
// WorkerRespawnsTotal and starts a new worker. This covers the
// ErrNetnsRestoreFailed path where process() calls runtime.Goexit() to
// retire a poisoned OS thread.
func (w *Watcher) superviseWorker(ctx context.Context) {
	defer w.wg.Done()
	for {
		workerExit := make(chan struct{})
		go func() {
			defer close(workerExit)
			w.worker(ctx)
		}()
		select {
		case <-ctx.Done():
			<-workerExit
			return
		case <-w.stopCh:
			<-workerExit
			return
		case <-workerExit:
			w.metrics.WorkerRespawnsTotal.Inc()
			w.logger.Error("worker exited; respawning")
			// Loop and spawn a replacement.
		}
	}
}

func (w *Watcher) worker(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case <-w.stopCh:
			return
		case item := <-w.workCh:
			w.process(ctx, item)
		}
	}
}

// ---------- Enqueue ----------

func (w *Watcher) enqueue(ctx context.Context, path string, track retryTrack, attempt int) {
	now := w.clock.Now()
	w.mu.Lock()
	st, ok := w.state[path]
	if !ok {
		st = &pathState{}
		w.state[path] = st
	}
	st.lastSeen = now
	if !st.nextEligible.IsZero() && now.Before(st.nextEligible) {
		w.mu.Unlock()
		return
	}
	w.mu.Unlock()

	item := workItem{netnsPath: path, track: track, attempt: attempt}
	select {
	case w.workCh <- item:
		return
	case <-ctx.Done():
		return
	case <-w.stopCh:
		return
	default:
	}

	// Transient backpressure: queue full at the moment of select. Record it
	// and fall through to a bounded retry. Successful send on retry =
	// backpressure-only. Failed send after enqueueRecoveryTimeout = drop.
	w.metrics.EnqueueBackpressureTotal.Inc()
	w.logger.Warn("work queue full, retrying with timeout", "netns", path)

	select {
	case w.workCh <- item:
	case <-w.clock.After(enqueueRecoveryTimeout):
		w.metrics.EnqueueDropsTotal.Inc()
		w.logger.Error("work queue still full after recovery window, dropping", "netns", path)
	case <-ctx.Done():
	case <-w.stopCh:
	}
}

// ---------- Sweep ----------

func (w *Watcher) sweeper(ctx context.Context) {
	defer w.wg.Done()
	w.sweep(ctx)
	t := w.clock.NewTicker(w.sweepInterval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-w.stopCh:
			return
		case <-t.C():
			w.sweep(ctx)
		}
	}
}

func (w *Watcher) sweep(ctx context.Context) {
	entries, err := os.ReadDir(w.dir)
	if err != nil {
		w.logger.Error("read dir", "dir", w.dir, "error", err.Error())
		return
	}
	live := make(map[string]struct{}, len(entries))
	for _, e := range entries {
		if ctx.Err() != nil {
			return
		}
		if !IsPodNetnsName(e.Name()) {
			continue
		}
		path := filepath.Join(w.dir, e.Name())
		live[path] = struct{}{}
		w.enqueue(ctx, path, trackNone, 0)
	}
	w.gcState(live)
	w.metrics.SweepsTotal.Inc()
}

func (w *Watcher) gcState(live map[string]struct{}) {
	w.mu.Lock()
	defer w.mu.Unlock()
	for path := range w.state {
		if _, alive := live[path]; !alive {
			delete(w.state, path)
		}
	}
}

// ---------- fsnotify ----------

func (w *Watcher) fsnotifyLoop(ctx context.Context) {
	defer w.wg.Done()
	fsw, err := fsnotify.NewWatcher()
	if err != nil {
		w.logger.Error("fsnotify new", "error", err.Error())
		return
	}
	defer fsw.Close()
	if err := fsw.Add(w.dir); err != nil {
		w.logger.Error("fsnotify add", "dir", w.dir, "error", err.Error())
		return
	}
	for {
		select {
		case <-ctx.Done():
			return
		case <-w.stopCh:
			return
		case err := <-fsw.Errors:
			if err != nil {
				w.logger.Error("fsnotify error", "error", err.Error())
			}
		case ev := <-fsw.Events:
			if ev.Op&fsnotify.Create == 0 {
				continue
			}
			base := filepath.Base(ev.Name)
			if !IsPodNetnsName(base) {
				continue
			}
			w.enqueue(ctx, ev.Name, trackNone, 0)
		}
	}
}

// ---------- Process ----------

func (w *Watcher) process(ctx context.Context, item workItem) {
	var res ReplacementResult
	var applyErr error
	err := w.opener.DoInNetns(item.netnsPath, func() error {
		var e error
		res, e = ApplyReplacement(w.factory(), w.dryRun)
		applyErr = e
		return e
	})

	if errors.Is(err, ErrNetnsRestoreFailed) {
		w.metrics.ThreadRetiredTotal.Inc()
		w.logger.Error("netns restore failed; retiring worker thread",
			"netns", item.netnsPath, "error", err.Error())
		runtime.Goexit()
	}

	w.mu.Lock()
	st := w.state[item.netnsPath]
	if st == nil {
		st = &pathState{}
		w.state[item.netnsPath] = st
	}
	now := w.clock.Now()
	defer w.mu.Unlock()

	switch {
	case err != nil:
		st.consecutiveFailures++
		w.metrics.ReplaceFailuresTotal.Inc()
		if st.consecutiveFailures >= CircuitBreakerMaxFailures {
			st.nextEligible = now.Add(CircuitBreakerCooldown)
			w.metrics.CircuitBreakerOpens.Inc()
			w.logger.Error("circuit breaker open",
				"netns", item.netnsPath, "failures", st.consecutiveFailures)
			return
		}
		w.scheduleRetry(ctx, item.netnsPath, trackFailure, st.consecutiveFailures)
	case applyErr == nil && res.Replaced == 0 && res.WouldReplace == 0 && res.Skipped == 0:
		st.tapNotFoundAttempts++
		if st.tapNotFoundAttempts > tapNotFoundAttemptsMax {
			return
		}
		w.scheduleRetry(ctx, item.netnsPath, trackTapNotPresent, st.tapNotFoundAttempts)
	default:
		st.consecutiveFailures = 0
		st.tapNotFoundAttempts = 0
		if res.Replaced > 0 {
			w.metrics.ReplacementsTotal.Add(float64(res.Replaced))
			w.logger.Info("qdisc replaced",
				"netns", item.netnsPath, "replaced", res.Replaced)
		}
		if res.WouldReplace > 0 {
			w.logger.Info("qdisc would replace (dry-run)",
				"netns", item.netnsPath, "would_replace", res.WouldReplace)
		}
	}
}

// computeBackoff is a pure function: delay = retryInitial << uint(attempt),
// capped at retryMax, clamped to retryMax if shift overflowed to <= 0. Each
// retry track (trackFailure, trackTapNotPresent) drives this independently
// from its own monotonic attempt counter in pathState — the two tracks
// never share a counter.
func (w *Watcher) computeBackoff(attempt int) time.Duration {
	delay := w.retryInitial << uint(attempt)
	if delay > w.retryMax || delay <= 0 {
		delay = w.retryMax
	}
	return delay
}

// scheduleRetry launches a goroutine that re-enqueues the path after the
// computed delay. `attempt` is the relevant track's counter (not a shared
// workItem.attempt), so the two tracks never cross-contaminate.
func (w *Watcher) scheduleRetry(ctx context.Context, path string, track retryTrack, attempt int) {
	delay := w.computeBackoff(attempt)
	w.wg.Add(1)
	go func() {
		defer w.wg.Done()
		select {
		case <-ctx.Done():
		case <-w.stopCh:
		case <-w.clock.After(delay):
			w.enqueue(ctx, path, track, attempt)
		}
	}()
}
