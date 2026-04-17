// proc_scanner_cmd is a one-shot diagnostic binary that walks /proc/*/ns/net,
// deduplicates by netns inode, and for each unique netns that is NOT the host
// netns attempts to replace the root qdisc on any tap*_kata device from "fq"
// to "pfifo_fast".
//
// This binary is a spike harness for issue #959. It is intentionally
// self-contained (no import of the sibling package main) so it can be built
// with a single `go build` invocation. The logic mirrors proc_scanner.go in
// the parent package exactly — the two should be kept in sync until the spike
// graduates to a proper internal package.
//
// Build:
//
//	cd cmd/kata-tap-qdisc-fix
//	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
//	    go build -o /tmp/proc_scanner ./proc_scanner_cmd/
//
// Deploy to test pod:
//
//	kubectl -n dev-debug cp /tmp/proc_scanner netns-debug:/tmp/proc_scanner
//	kubectl -n dev-debug exec -it netns-debug -- /tmp/proc_scanner --log-level debug
package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/vishvananda/netlink"
	vnetns "github.com/vishvananda/netns"
)

// ---------- entry point ----------

func main() { os.Exit(run()) }

func run() int {
	dryRun := flag.Bool("dry-run", false, "inspect qdiscs but do not replace them")
	procRoot := flag.String("proc", "/proc", "proc filesystem root (use /host/proc inside a hostPID=true container)")
	logLevelStr := flag.String("log-level", "info", "log level: debug|info|warn|error")
	flag.Parse()

	handler := slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: parseLevel(*logLevelStr)})
	logger := slog.New(handler)
	logger.Info("proc-scanner starting", "dry_run", *dryRun, "proc", *procRoot)

	// Capture host netns inode from PID 1.
	hostInode, err := hostNetnsInode(*procRoot, 1)
	if err != nil {
		logger.Error("read host netns inode", "error", err.Error())
		return 3
	}
	logger.Info("host netns inode", "inode", hostInode)

	// Capture host netns handle (must happen before any goroutine does setns).
	if err := initHostNetns(); err != nil {
		logger.Error("init host netns", "error", err.Error())
		return 3
	}

	result, err := sweep(context.Background(), *procRoot, hostInode, *dryRun, logger)
	if err != nil {
		logger.Error("sweep failed", "error", err.Error())
		return 1
	}

	fmt.Println()
	fmt.Println("=== proc sweep result ===")
	fmt.Printf("elapsed:       %v\n", result.elapsed)
	fmt.Printf("total_inodes:  %d\n", result.totalInodes)
	fmt.Printf("host_skipped:  %d\n", result.hostSkipped)
	fmt.Printf("unique_netns:  %d\n", result.uniqueNetns)
	fmt.Printf("taps_found:    %d\n", result.tapsFound)
	fmt.Printf("replaced:      %d\n", result.replaced)
	fmt.Printf("would_replace: %d\n", result.wouldReplace)
	fmt.Println("=========================")
	return 0
}

// ---------- sweep ----------

type sweepResult struct {
	elapsed      time.Duration
	totalInodes  int
	hostSkipped  int
	uniqueNetns  int
	tapsFound    int
	replaced     int
	wouldReplace int
}

func sweep(ctx context.Context, procRoot string, hostInode uint64, dryRun bool, logger *slog.Logger) (sweepResult, error) {
	start := time.Now()
	var res sweepResult

	entries, err := os.ReadDir(procRoot)
	if err != nil {
		return res, fmt.Errorf("readdir %s: %w", procRoot, err)
	}

	seen := make(map[uint64]string, 256)

	for _, entry := range entries {
		if ctx.Err() != nil {
			return res, ctx.Err()
		}
		if !isPidDir(entry) {
			continue
		}
		nsPath := filepath.Join(procRoot, entry.Name(), "ns", "net")
		inode, err := statInode(nsPath)
		if err != nil {
			logger.Debug("stat netns; process likely exited", "pid", entry.Name(), "error", err.Error())
			continue
		}
		res.totalInodes++
		if inode == hostInode {
			res.hostSkipped++
			continue
		}
		if _, ok := seen[inode]; !ok {
			seen[inode] = nsPath
		}
	}

	res.uniqueNetns = len(seen)

	for inode, nsPath := range seen {
		if ctx.Err() != nil {
			return res, ctx.Err()
		}

		r, err := doInNetns(nsPath, func() (replacementResult, error) {
			return applyReplacement(dryRun, logger)
		})
		if err != nil {
			logger.Debug("enter netns failed; skipping", "inode", inode, "path", nsPath, "error", err.Error())
			continue
		}
		res.tapsFound += r.replaced + r.wouldReplace + r.skipped
		res.replaced += r.replaced
		res.wouldReplace += r.wouldReplace

		if r.replaced > 0 || r.wouldReplace > 0 {
			logger.Info("tap qdisc action",
				"inode", inode, "path", nsPath,
				"replaced", r.replaced, "would_replace", r.wouldReplace)
		}
	}

	res.elapsed = time.Since(start)
	return res, nil
}

// ---------- qdisc replacement ----------

var kataTapRE = regexp.MustCompile(`^tap[0-9]+_kata$`)

type replacementResult struct {
	replaced     int
	wouldReplace int
	skipped      int
}

func applyReplacement(dryRun bool, logger *slog.Logger) (replacementResult, error) {
	var res replacementResult
	links, err := netlink.LinkList()
	if err != nil {
		return res, fmt.Errorf("list links: %w", err)
	}
	for _, link := range links {
		name := link.Attrs().Name
		if !kataTapRE.MatchString(name) {
			continue
		}
		rootQdisc := ""
		qdiscs, _ := netlink.QdiscList(link)
		for _, q := range qdiscs {
			if q.Attrs().Parent == netlink.HANDLE_ROOT {
				rootQdisc = q.Type()
				break
			}
		}
		logger.Debug("tap device found", "name", name, "root_qdisc", rootQdisc)
		if rootQdisc != "fq" {
			res.skipped++
			continue
		}
		if dryRun {
			logger.Info("dry-run: would replace qdisc", "device", name, "from", "fq", "to", "pfifo_fast")
			res.wouldReplace++
			continue
		}
		q := &netlink.GenericQdisc{
			QdiscAttrs: netlink.QdiscAttrs{
				LinkIndex: link.Attrs().Index,
				Parent:    netlink.HANDLE_ROOT,
			},
			QdiscType: "pfifo_fast",
		}
		if err := netlink.QdiscReplace(q); err != nil {
			return res, fmt.Errorf("replace qdisc on %s: %w", name, err)
		}
		logger.Info("replaced qdisc", "device", name, "from", "fq", "to", "pfifo_fast")
		res.replaced++
	}
	return res, nil
}

// ---------- netns helpers ----------

var (
	hostNs    vnetns.NsHandle
	hostNsErr error
)

// initHostNetns captures the current goroutine's network namespace as the
// canonical host netns. Must be called from the main goroutine before any
// setns calls.
func initHostNetns() error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	hostNs, hostNsErr = vnetns.Get()
	return hostNsErr
}

// doInNetns enters the netns described by path (a /proc/<pid>/ns/net symlink),
// calls fn, then restores the host netns. Thread-safe via LockOSThread.
func doInNetns(path string, fn func() (replacementResult, error)) (replacementResult, error) {
	var zero replacementResult

	runtime.LockOSThread()
	unlockThread := true
	defer func() {
		if err := vnetns.Set(hostNs); err != nil {
			unlockThread = false
			// We poisoned the thread — but this is a one-shot binary so just
			// log and let the process exit.
			fmt.Fprintf(os.Stderr, "FATAL: netns restore failed: %v\n", err)
			os.Exit(2)
		}
		if unlockThread {
			runtime.UnlockOSThread()
		}
	}()

	target, err := vnetns.GetFromPath(path)
	if err != nil {
		return zero, fmt.Errorf("get netns from %s: %w", path, err)
	}
	defer target.Close()

	if err := vnetns.Set(target); err != nil {
		return zero, fmt.Errorf("enter netns %s: %w", path, err)
	}
	return fn()
}

// ---------- proc helpers ----------

func isPidDir(e os.DirEntry) bool {
	if !e.IsDir() {
		return false
	}
	for _, c := range e.Name() {
		if c < '0' || c > '9' {
			return false
		}
	}
	return len(e.Name()) > 0
}

func statInode(path string) (uint64, error) {
	var st syscall.Stat_t
	if err := syscall.Stat(path, &st); err != nil {
		return 0, err
	}
	return st.Ino, nil
}

func hostNetnsInode(procRoot string, pid int) (uint64, error) {
	path := filepath.Join(procRoot, strconv.Itoa(pid), "ns", "net")
	return statInode(path)
}

// ---------- misc ----------

func parseLevel(s string) slog.Level {
	switch strings.ToLower(s) {
	case "debug":
		return slog.LevelDebug
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}
