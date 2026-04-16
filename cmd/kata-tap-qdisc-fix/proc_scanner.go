package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// ScanResult summarises one Sweep pass through /proc.
type ScanResult struct {
	// TotalInodes is the number of /proc/<pid>/ns/net symlinks read (including
	// duplicates — i.e. one per numeric /proc entry that was readable).
	TotalInodes int
	// UniqueNetns is the number of distinct netns inodes visited.
	UniqueNetns int
	// HostSkipped is the number of /proc/<pid>/ns/net entries that matched the
	// host netns inode and were skipped.
	HostSkipped int
	// TapsFound is the total number of tap*_kata devices whose qdiscs were
	// inspected (Replaced + WouldReplace + Skipped across all netns).
	TapsFound int
	// Replaced is the total number of qdiscs actually replaced.
	Replaced int
	// WouldReplace is the total number of qdiscs that would be replaced (dry-run).
	WouldReplace int
	// Elapsed is the wall-time of the Sweep call.
	Elapsed time.Duration
}

// ProcScanner walks /proc/*/ns/net, deduplicates by netns inode, and for each
// unique netns that is not the host netns, invokes ApplyReplacement via the
// same opener/factory pattern as Watcher. It is intentionally additive — the
// existing Watcher is not modified.
type ProcScanner struct {
	opener      NetnsOpener
	factory     QdiscManagerFactory
	dryRun      bool
	logger      *slog.Logger
	hostInode   uint64
	procRoot    string // injectable for tests; defaults to "/proc"
}

// NewProcScanner creates a ProcScanner. hostInode is the inode of the host
// netns (typically obtained by reading /proc/1/ns/net at startup). procRoot is
// the root of the proc filesystem ("/proc" in production; overridable in tests).
func NewProcScanner(
	opener NetnsOpener,
	factory QdiscManagerFactory,
	dryRun bool,
	logger *slog.Logger,
	hostInode uint64,
	procRoot string,
) *ProcScanner {
	if procRoot == "" {
		procRoot = "/proc"
	}
	return &ProcScanner{
		opener:    opener,
		factory:   factory,
		dryRun:    dryRun,
		logger:    logger,
		hostInode: hostInode,
		procRoot:  procRoot,
	}
}

// HostNetnsInode reads the inode of the host network namespace from
// /proc/<pid>/ns/net (typically pid=1). Returns the inode number on success.
func HostNetnsInode(procRoot string, pid int) (uint64, error) {
	path := filepath.Join(procRoot, strconv.Itoa(pid), "ns", "net")
	var st syscall.Stat_t
	if err := syscall.Stat(path, &st); err != nil {
		return 0, fmt.Errorf("stat %s: %w", path, err)
	}
	return st.Ino, nil
}

// Sweep walks procRoot/*/ns/net, deduplicates by inode, and runs
// ApplyReplacement in each unique non-host netns.
func (p *ProcScanner) Sweep(ctx context.Context) (ScanResult, error) {
	start := time.Now()
	var result ScanResult

	entries, err := os.ReadDir(p.procRoot)
	if err != nil {
		return result, fmt.Errorf("readdir %s: %w", p.procRoot, err)
	}

	// Map: inode → representative /proc/<pid>/ns/net path for that netns.
	// We use the first pid we encounter for a given inode.
	seen := make(map[uint64]string, 256)

	for _, entry := range entries {
		if ctx.Err() != nil {
			return result, ctx.Err()
		}
		// Only numeric directory names are PIDs.
		if !isPidEntry(entry) {
			continue
		}

		nsPath := filepath.Join(p.procRoot, entry.Name(), "ns", "net")
		inode, err := inodeOf(nsPath)
		if err != nil {
			// ENOENT / ESRCH: process exited between ReadDir and Stat — benign.
			p.logger.Debug("proc netns stat failed; process likely exited",
				"pid", entry.Name(), "error", err.Error())
			continue
		}

		result.TotalInodes++

		if inode == p.hostInode {
			result.HostSkipped++
			continue
		}

		if _, alreadySeen := seen[inode]; alreadySeen {
			// Duplicate — same netns shared by another proc entry.
			continue
		}
		seen[inode] = nsPath
	}

	result.UniqueNetns = len(seen)

	// Now visit each unique netns.
	for inode, nsPath := range seen {
		if ctx.Err() != nil {
			return result, ctx.Err()
		}

		var res ReplacementResult
		err := p.opener.DoInNetns(nsPath, func() error {
			var applyErr error
			res, applyErr = ApplyReplacement(p.factory(), p.dryRun)
			return applyErr
		})
		if err != nil {
			p.logger.Debug("sweep: enter netns failed; skipping",
				"inode", inode, "path", nsPath, "error", err.Error())
			continue
		}

		result.TapsFound += res.Replaced + res.WouldReplace + res.Skipped
		result.Replaced += res.Replaced
		result.WouldReplace += res.WouldReplace

		if res.Replaced > 0 {
			p.logger.Info("proc sweep: qdisc replaced",
				"inode", inode, "path", nsPath, "replaced", res.Replaced)
		} else if res.WouldReplace > 0 {
			p.logger.Info("proc sweep: qdisc would replace (dry-run)",
				"inode", inode, "path", nsPath, "would_replace", res.WouldReplace)
		}
	}

	result.Elapsed = time.Since(start)
	return result, nil
}

// isPidEntry returns true when the DirEntry represents a numeric directory
// name (i.e. a PID under /proc).
func isPidEntry(e os.DirEntry) bool {
	if !e.IsDir() {
		return false
	}
	name := e.Name()
	for _, c := range name {
		if c < '0' || c > '9' {
			return false
		}
	}
	return len(name) > 0
}

// inodeOf returns the inode of the file at path via syscall.Stat.
// For /proc/<pid>/ns/net this resolves through the symlink to the actual
// netns inode — which is what we want for deduplication.
func inodeOf(path string) (uint64, error) {
	var st syscall.Stat_t
	// syscall.Stat follows symlinks (unlike Lstat), so we get the netns inode.
	if err := syscall.Stat(path, &st); err != nil {
		return 0, err
	}
	return st.Ino, nil
}

// formatScanResult formats a ScanResult as a human-readable multiline string
// suitable for printing to stdout.
func formatScanResult(r ScanResult) string {
	var sb strings.Builder
	fmt.Fprintf(&sb, "elapsed:        %v\n", r.Elapsed)
	fmt.Fprintf(&sb, "total_inodes:   %d\n", r.TotalInodes)
	fmt.Fprintf(&sb, "host_skipped:   %d\n", r.HostSkipped)
	fmt.Fprintf(&sb, "unique_netns:   %d\n", r.UniqueNetns)
	fmt.Fprintf(&sb, "taps_found:     %d\n", r.TapsFound)
	fmt.Fprintf(&sb, "replaced:       %d\n", r.Replaced)
	fmt.Fprintf(&sb, "would_replace:  %d\n", r.WouldReplace)
	return sb.String()
}
