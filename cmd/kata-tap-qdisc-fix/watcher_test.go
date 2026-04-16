package main

import (
	"context"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

// ---------- fake clock ----------

type fakeTimer struct {
	when time.Time
	ch   chan time.Time
}

type fakeTicker struct {
	d    time.Duration
	next time.Time
	ch   chan time.Time
}

func (f *fakeTicker) C() <-chan time.Time { return f.ch }
func (f *fakeTicker) Stop()               {}

type fakeClock struct {
	mu      sync.Mutex
	now     time.Time
	timers  []*fakeTimer
	tickers []*fakeTicker
}

func newFakeClock() *fakeClock {
	return &fakeClock{now: time.Unix(0, 0)}
}

func (f *fakeClock) Now() time.Time {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.now
}

func (f *fakeClock) After(d time.Duration) <-chan time.Time {
	f.mu.Lock()
	defer f.mu.Unlock()
	ch := make(chan time.Time, 1)
	f.timers = append(f.timers, &fakeTimer{when: f.now.Add(d), ch: ch})
	return ch
}

func (f *fakeClock) NewTicker(d time.Duration) Ticker {
	f.mu.Lock()
	defer f.mu.Unlock()
	t := &fakeTicker{d: d, next: f.now.Add(d), ch: make(chan time.Time, 1)}
	f.tickers = append(f.tickers, t)
	return t
}

// Advance moves virtual time forward and fires all timers/tickers whose
// deadline falls within the new window. Safe to call from tests.
func (f *fakeClock) Advance(d time.Duration) {
	f.mu.Lock()
	f.now = f.now.Add(d)
	now := f.now
	remaining := f.timers[:0]
	for _, t := range f.timers {
		if !t.when.After(now) {
			select {
			case t.ch <- now:
			default:
			}
		} else {
			remaining = append(remaining, t)
		}
	}
	f.timers = remaining
	for _, t := range f.tickers {
		for !t.next.After(now) {
			select {
			case t.ch <- t.next:
			default:
			}
			t.next = t.next.Add(t.d)
		}
	}
	f.mu.Unlock()
}

// ---------- opener ----------

type perPathOpener struct {
	mu       sync.Mutex
	current  string
	paths    []string
	managers map[string]*fakeQdiscManager
}

func (o *perPathOpener) DoInNetns(path string, fn func() error) error {
	o.mu.Lock()
	o.current = path
	o.paths = append(o.paths, path)
	o.mu.Unlock()
	return fn()
}

func (o *perPathOpener) factoryFor() QdiscManagerFactory {
	return func() QdiscManager {
		o.mu.Lock()
		defer o.mu.Unlock()
		return o.managers[o.current]
	}
}

func (o *perPathOpener) Paths() []string {
	o.mu.Lock()
	defer o.mu.Unlock()
	return append([]string(nil), o.paths...)
}

func newOpener(mgrs map[string]*fakeQdiscManager) *perPathOpener {
	return &perPathOpener{managers: mgrs}
}

func discardLogger() *slog.Logger {
	return slog.New(slog.NewJSONHandler(io.Discard, nil))
}

// waitFor polls a condition until it returns true or the wall-clock deadline
// passes. Wall time is used ONLY as a safety net so tests fail loudly instead
// of hanging CI; the functional timing under test is virtual via fakeClock.
func waitFor(t *testing.T, cond func() bool, msg string) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for: %s", msg)
}

// ---------- tests ----------

func TestWatcherInitialSweepProcessesOnlyCniFilesAndUsesPerPathManager(t *testing.T) {
	dir := t.TempDir()
	mgrs := map[string]*fakeQdiscManager{
		filepath.Join(dir, "cni-abc"): {links: []LinkInfo{{Name: "tap0_kata", RootQdiscType: "fq"}}},
		filepath.Join(dir, "cni-def"): {links: []LinkInfo{{Name: "tap0_kata", RootQdiscType: "fq"}}},
	}
	for name := range mgrs {
		if err := os.WriteFile(name, nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(dir, "garbage-file"), nil, 0o644); err != nil {
		t.Fatal(err)
	}

	opener := newOpener(mgrs)
	clk := newFakeClock()
	w := NewWatcher(dir, opener, opener.factoryFor(), false, 60*time.Second, newTestMetrics(), discardLogger(), clk)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	w.Start(ctx)
	defer w.Stop()

	waitFor(t, func() bool { return len(opener.Paths()) >= 2 }, "2 paths processed via initial sweep")
	if got := len(opener.Paths()); got != 2 {
		t.Errorf("paths processed = %d, want 2", got)
	}
	for path, fake := range mgrs {
		fake.mu.Lock()
		calls := append([]string(nil), fake.replaceCalls...)
		fake.mu.Unlock()
		if len(calls) != 1 || calls[0] != "tap0_kata" {
			t.Errorf("mgr %s replaceCalls = %v, want [tap0_kata]", path, calls)
		}
	}
}

func TestWatcherRetriesWhenTapNotYetPresent(t *testing.T) {
	dir := t.TempDir()
	// Name must pass IsPodNetnsName (hex chars only after "cni-").
	path := filepath.Join(dir, "cni-1a7e")
	if err := os.WriteFile(path, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	fake := &fakeQdiscManager{links: []LinkInfo{}} // no tap present yet
	opener := newOpener(map[string]*fakeQdiscManager{path: fake})
	clk := newFakeClock()
	w := NewWatcher(dir, opener, opener.factoryFor(), false, 60*time.Second, newTestMetrics(), discardLogger(), clk)
	w.setRetryBackoffForTest(10*time.Millisecond, 20*time.Millisecond)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	w.Start(ctx)
	defer w.Stop()

	waitFor(t, func() bool { return len(opener.Paths()) >= 1 }, "first attempt made")

	// Now the tap appears.
	fake.mu.Lock()
	fake.links = []LinkInfo{{Name: "tap0_kata", RootQdiscType: "fq"}}
	fake.mu.Unlock()

	// Fire the retry timer by advancing virtual time past the backoff.
	// scheduleRetry is called with attempt=1, so delay = retryInitial<<1 = 20ms;
	// advance 25ms to ensure the timer fires.
	clk.Advance(25 * time.Millisecond)

	waitFor(t, func() bool {
		fake.mu.Lock()
		defer fake.mu.Unlock()
		return len(fake.replaceCalls) > 0
	}, "replacement after retry fires")
}

func TestWatcherReactsToCreateEvent(t *testing.T) {
	dir := t.TempDir()
	// Name must pass IsPodNetnsName (hex chars only after "cni-").
	path := filepath.Join(dir, "cni-a1b2")
	fake := &fakeQdiscManager{links: []LinkInfo{{Name: "tap0_kata", RootQdiscType: "fq"}}}
	opener := newOpener(map[string]*fakeQdiscManager{path: fake})
	clk := newFakeClock()
	w := NewWatcher(dir, opener, opener.factoryFor(), false, 60*time.Second, newTestMetrics(), discardLogger(), clk)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	w.Start(ctx)
	defer w.Stop()

	// fsnotify registration is synchronous; no virtual-time advance needed.
	if err := os.WriteFile(path, nil, 0o644); err != nil {
		t.Fatal(err)
	}

	waitFor(t, func() bool {
		fake.mu.Lock()
		defer fake.mu.Unlock()
		return len(fake.replaceCalls) > 0
	}, "replacement after fsnotify create")
}

func TestWatcherCircuitBreakerAfterConsecutiveFailures(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "cni-bad")
	if err := os.WriteFile(path, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	errs := make([]error, 20)
	for i := range errs {
		errs[i] = errRetryable("boom")
	}
	fake := &fakeQdiscManager{
		links:         []LinkInfo{{Name: "tap0_kata", RootQdiscType: "fq"}},
		replaceErrors: errs,
	}
	opener := newOpener(map[string]*fakeQdiscManager{path: fake})
	clk := newFakeClock()
	w := NewWatcher(dir, opener, opener.factoryFor(), false, 60*time.Second, newTestMetrics(), discardLogger(), clk)
	w.setRetryBackoffForTest(1*time.Millisecond, 2*time.Millisecond)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	w.Start(ctx)
	defer w.Stop()

	// Wait for the initial sweep to process the first attempt before
	// advancing virtual time — ensures all retry timers are registered.
	waitFor(t, func() bool {
		fake.mu.Lock()
		defer fake.mu.Unlock()
		return len(fake.replaceCalls) >= 1
	}, "initial attempt made")

	// Advance virtual time so every pending retry timer fires. Interleave
	// brief real-time yields so timer goroutines can run between advances.
	for i := 0; i < 30; i++ {
		clk.Advance(5 * time.Millisecond)
		time.Sleep(2 * time.Millisecond)
	}
	waitFor(t, func() bool {
		fake.mu.Lock()
		defer fake.mu.Unlock()
		return len(fake.replaceCalls) >= CircuitBreakerMaxFailures
	}, "breaker threshold reached")

	fake.mu.Lock()
	got := len(fake.replaceCalls)
	fake.mu.Unlock()
	if got > CircuitBreakerMaxFailures {
		t.Errorf("replaceCalls = %d, want <= %d (breaker should stop retries)", got, CircuitBreakerMaxFailures)
	}
}

func TestWatcherExponentialBackoffCapsBothTracks(t *testing.T) {
	clk := newFakeClock()
	w := NewWatcher(t.TempDir(), nil, nil, false, 60*time.Second, newTestMetrics(), discardLogger(), clk)
	w.setRetryBackoffForTest(10*time.Millisecond, 200*time.Millisecond)

	for attempt := 0; attempt <= 40; attempt++ {
		delay := w.computeBackoff(attempt)
		if delay <= 0 {
			t.Fatalf("attempt=%d: delay <= 0 (got %v)", attempt, delay)
		}
		if delay > 200*time.Millisecond {
			t.Fatalf("attempt=%d: delay %v exceeds retryMax (200ms)", attempt, delay)
		}
	}
}

// TestEnqueueMetricsSplitBackpressureVsDrops asserts that the "queue full"
// path increments _backpressure_total on transient full, and _drops_total
// only after the 1s recovery window elapses without space freeing up.
func TestEnqueueMetricsSplitBackpressureVsDrops(t *testing.T) {
	dir := t.TempDir()
	clk := newFakeClock()
	metrics := newTestMetrics()
	opener := newOpener(map[string]*fakeQdiscManager{})
	w := NewWatcher(dir, opener, opener.factoryFor(), false, 60*time.Second, metrics, discardLogger(), clk)
	w.workCh = make(chan workItem) // unbuffered → every second enqueue blocks
	w.setRetryBackoffForTest(1*time.Millisecond, 2*time.Millisecond)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Don't Start() — we want the channel NOT drained so enqueue is forced
	// down the backpressure path. Call enqueue directly.
	done := make(chan struct{})
	go func() {
		// track=0 (trackNone), attempt=0
		w.enqueue(ctx, filepath.Join(dir, "cni-f1a5"), 0, 0)
		close(done)
	}()

	// Wait until the enqueue goroutine has incremented backpressure_total
	// (which means it has called clock.After and registered the timer).
	waitFor(t, func() bool {
		return testCounterValue(t, metrics.EnqueueBackpressureTotal) >= 1
	}, "backpressure counter incremented (After registered)")

	// Advance the fake clock past the 1s recovery window; timer fires
	// which increments drops.
	clk.Advance(1100 * time.Millisecond)

	<-done
	// backpressure_total was already confirmed ≥1 by waitFor above; recheck exact value.
	if got := testCounterValue(t, metrics.EnqueueBackpressureTotal); got != 1 {
		t.Errorf("backpressure_total = %d, want 1", got)
	}
	if got := testCounterValue(t, metrics.EnqueueDropsTotal); got != 1 {
		t.Errorf("drops_total = %d, want 1", got)
	}
}

// TestWorkerRespawnsOnPoisonedThread asserts the supervisor restarts the
// worker when the underlying goroutine exits via runtime.Goexit().
func TestWorkerRespawnsOnPoisonedThread(t *testing.T) {
	dir := t.TempDir()
	// Name must pass IsPodNetnsName (hex chars only after "cni-").
	path := filepath.Join(dir, "cni-b01d")
	if err := os.WriteFile(path, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	// First call poisons the thread (ErrNetnsRestoreFailed); worker should
	// Goexit, supervisor respawns, second enqueue succeeds.
	fake := &fakeQdiscManager{links: []LinkInfo{{Name: "tap0_kata", RootQdiscType: "fq"}}}
	opener := &poisoningOpener{inner: newOpener(map[string]*fakeQdiscManager{path: fake}), poisonOnce: true}
	clk := newFakeClock()
	metrics := newTestMetrics()
	w := NewWatcher(dir, opener, opener.inner.factoryFor(), false, 60*time.Second, metrics, discardLogger(), clk)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	w.Start(ctx)
	defer w.Stop()

	// Poison then recover. Wait for respawn counter to bump.
	waitFor(t, func() bool { return testCounterValue(t, metrics.WorkerRespawnsTotal) >= 1 }, "worker respawned after poison")

	// Now a second trigger should process normally.
	// track=0 (trackNone), attempt=0
	w.enqueue(ctx, path, 0, 0)
	waitFor(t, func() bool {
		fake.mu.Lock()
		defer fake.mu.Unlock()
		return len(fake.replaceCalls) >= 1
	}, "replacement after respawn")
}

type poisoningOpener struct {
	inner      *perPathOpener
	poisonOnce bool
	mu         sync.Mutex
}

func (p *poisoningOpener) DoInNetns(path string, fn func() error) error {
	p.mu.Lock()
	poison := p.poisonOnce
	p.poisonOnce = false
	p.mu.Unlock()
	if poison {
		return ErrNetnsRestoreFailed
	}
	return p.inner.DoInNetns(path, fn)
}

type errRetryable string

func (e errRetryable) Error() string { return string(e) }
