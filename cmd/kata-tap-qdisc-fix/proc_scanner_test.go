package main

import (
	"context"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strconv"
	"syscall"
	"testing"
)

// ---------- helpers ----------

func silentLogger() *slog.Logger {
	return slog.New(slog.NewJSONHandler(io.Discard, nil))
}

// buildFakeProcTree creates a minimal /proc-like directory tree under root.
//
//	pids:    each entry creates /proc/<pid>/ with a symlink at ns/net pointing
//	         to a "netns file" identified by netnsID (a synthetic unique name).
//	nsFiles: map of netnsID → the actual file that will be the link target.
//	         The function creates a real file for each unique nsID so that
//	         syscall.Stat can resolve the inode.
//
// Returns a map from netnsID → inode so callers can build expectations.
func buildFakeProcTree(t *testing.T, root string, pidToNsID map[int]string) (nsIDToInode map[string]uint64) {
	t.Helper()
	nsDir := filepath.Join(root, "_netns_files")
	if err := os.MkdirAll(nsDir, 0o755); err != nil {
		t.Fatal(err)
	}

	// Create one real file per unique nsID.
	nsIDToInode = make(map[string]uint64)
	for _, nsID := range pidToNsID {
		if _, ok := nsIDToInode[nsID]; ok {
			continue
		}
		nsFile := filepath.Join(nsDir, nsID)
		if err := os.WriteFile(nsFile, nil, 0o644); err != nil {
			t.Fatal(err)
		}
		var st syscall.Stat_t
		if err := syscall.Stat(nsFile, &st); err != nil {
			t.Fatal(err)
		}
		nsIDToInode[nsID] = st.Ino
	}

	// Build /proc/<pid>/ns/net symlinks.
	for pid, nsID := range pidToNsID {
		pidStr := strconv.Itoa(pid)
		nsSubdir := filepath.Join(root, pidStr, "ns")
		if err := os.MkdirAll(nsSubdir, 0o755); err != nil {
			t.Fatal(err)
		}
		target := filepath.Join(nsDir, nsID)
		linkPath := filepath.Join(nsSubdir, "net")
		if err := os.Symlink(target, linkPath); err != nil {
			t.Fatal(err)
		}
	}
	return nsIDToInode
}

// ---------- tests ----------

// TestProcScannerDedup verifies that 3 processes sharing 2 distinct netns
// result in exactly 2 unique netns sweeps.
func TestProcScannerDedup(t *testing.T) {
	root := t.TempDir()

	// PID 100 and 101 share nsA; PID 200 is in nsB.
	pidToNsID := map[int]string{
		100: "nsA",
		101: "nsA",
		200: "nsB",
	}
	nsIDToInode := buildFakeProcTree(t, root, pidToNsID)

	// Use a hostInode that doesn't match any of our fake netns inodes.
	const hostInode = uint64(999999999)

	// countingOpener tracks how many times DoInNetns is called.
	var sweepCount int
	opener := &countingOpener{fn: func(_ string) { sweepCount++ }}

	scanner := NewProcScanner(
		opener,
		func() QdiscManager { return &fakeQdiscManager{links: nil} },
		false,
		silentLogger(),
		hostInode,
		root,
	)

	result, err := scanner.Sweep(context.Background())
	if err != nil {
		t.Fatalf("Sweep() error: %v", err)
	}

	if sweepCount != 2 {
		t.Errorf("DoInNetns called %d times, want 2 (one per unique netns)", sweepCount)
	}
	if result.UniqueNetns != 2 {
		t.Errorf("UniqueNetns = %d, want 2", result.UniqueNetns)
	}
	if result.TotalInodes != 3 {
		t.Errorf("TotalInodes = %d, want 3", result.TotalInodes)
	}
	if result.HostSkipped != 0 {
		t.Errorf("HostSkipped = %d, want 0", result.HostSkipped)
	}
	// Confirm we have entries for both nsIDs.
	_ = nsIDToInode
}

// TestProcScannerSkipsHostNetns verifies that entries whose inode matches the
// host netns inode are counted in HostSkipped and NOT swept.
func TestProcScannerSkipsHostNetns(t *testing.T) {
	root := t.TempDir()

	// Two PIDs share nsA (will be treated as host). One PID in nsB.
	pidToNsID := map[int]string{
		1:   "nsA",
		2:   "nsA",
		100: "nsB",
	}
	nsIDToInode := buildFakeProcTree(t, root, pidToNsID)
	hostInode := nsIDToInode["nsA"]

	var sweepCount int
	opener := &countingOpener{fn: func(_ string) { sweepCount++ }}

	scanner := NewProcScanner(
		opener,
		func() QdiscManager { return &fakeQdiscManager{links: nil} },
		false,
		silentLogger(),
		hostInode,
		root,
	)

	result, err := scanner.Sweep(context.Background())
	if err != nil {
		t.Fatalf("Sweep() error: %v", err)
	}

	if sweepCount != 1 {
		t.Errorf("DoInNetns called %d times, want 1 (only nsB)", sweepCount)
	}
	if result.UniqueNetns != 1 {
		t.Errorf("UniqueNetns = %d, want 1", result.UniqueNetns)
	}
	if result.HostSkipped != 2 {
		t.Errorf("HostSkipped = %d, want 2 (both nsA entries)", result.HostSkipped)
	}
}

// TestProcScannerToleratesEnoent verifies that a /proc/<pid>/ns/net path that
// disappears between ReadDir and Stat (simulating a transient proc entry) does
// NOT cause Sweep to return an error — it logs debug and continues.
func TestProcScannerToleratesEnoent(t *testing.T) {
	root := t.TempDir()

	// PID 100 → nsA (stable). PID 200 → symlink to a non-existent target
	// (simulates ENOENT).
	nsDir := filepath.Join(root, "_netns_files")
	if err := os.MkdirAll(nsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	realNsFile := filepath.Join(nsDir, "nsA")
	if err := os.WriteFile(realNsFile, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	var st syscall.Stat_t
	if err := syscall.Stat(realNsFile, &st); err != nil {
		t.Fatal(err)
	}
	hostInode := uint64(999999999)

	// Stable pid 100.
	pid100ns := filepath.Join(root, "100", "ns")
	if err := os.MkdirAll(pid100ns, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(realNsFile, filepath.Join(pid100ns, "net")); err != nil {
		t.Fatal(err)
	}

	// Transient pid 200 — symlink target does NOT exist.
	pid200ns := filepath.Join(root, "200", "ns")
	if err := os.MkdirAll(pid200ns, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(nsDir, "gone"), filepath.Join(pid200ns, "net")); err != nil {
		t.Fatal(err)
	}

	var sweepCount int
	opener := &countingOpener{fn: func(_ string) { sweepCount++ }}

	scanner := NewProcScanner(
		opener,
		func() QdiscManager { return &fakeQdiscManager{links: nil} },
		false,
		silentLogger(),
		hostInode,
		root,
	)

	result, err := scanner.Sweep(context.Background())
	if err != nil {
		t.Fatalf("Sweep() returned error on ENOENT: %v", err)
	}

	// Only pid 100 should be swept (pid 200 silently skipped).
	if sweepCount != 1 {
		t.Errorf("DoInNetns called %d times, want 1", sweepCount)
	}
	if result.TotalInodes != 1 {
		t.Errorf("TotalInodes = %d, want 1 (only stat-able entry)", result.TotalInodes)
	}
}

// TestProcScannerCountsReplacements verifies that the ScanResult fields are
// correctly aggregated across multiple netns.
func TestProcScannerCountsReplacements(t *testing.T) {
	root := t.TempDir()

	pidToNsID := map[int]string{
		100: "nsA",
		200: "nsB",
	}
	nsIDToInode := buildFakeProcTree(t, root, pidToNsID)

	const hostInode = uint64(999999999)

	// nsA has a tap0_kata with fq (will be replaced).
	// nsB has no tap.
	nsAPath := filepath.Join(root, "_netns_files", "nsA")
	nsBPath := filepath.Join(root, "_netns_files", "nsB")

	managerByFile := map[string]*fakeQdiscManager{
		nsAPath: {links: []LinkInfo{{Name: "tap0_kata", RootQdiscType: "fq"}}},
		nsBPath: {links: []LinkInfo{{Name: "eth0", RootQdiscType: "noqueue"}}},
	}

	// The opener resolves which manager to use by the path passed to DoInNetns.
	// Because Sweep uses the first pid's path (e.g. /proc/100/ns/net → symlink
	// to nsA file), we need a smarter fake that reads through the symlink.
	opener := &resolveOpener{managerByFile: managerByFile}

	scanner := NewProcScanner(
		opener,
		opener.factory(),
		false,
		silentLogger(),
		hostInode,
		root,
	)

	result, err := scanner.Sweep(context.Background())
	if err != nil {
		t.Fatalf("Sweep() error: %v", err)
	}

	if result.UniqueNetns != 2 {
		t.Errorf("UniqueNetns = %d, want 2", result.UniqueNetns)
	}
	if result.Replaced != 1 {
		t.Errorf("Replaced = %d, want 1", result.Replaced)
	}
	if result.TapsFound != 1 {
		t.Errorf("TapsFound = %d, want 1", result.TapsFound)
	}

	_ = nsIDToInode
}

// ---------- countingOpener ----------

type countingOpener struct {
	fn func(path string)
}

func (c *countingOpener) DoInNetns(path string, fn func() error) error {
	c.fn(path)
	return fn()
}

// ---------- resolveOpener ----------
// Opens a symlink path and resolves it to the real file, then delegates to a
// per-real-file manager map. This mirrors what the real opener does (enter the
// netns referred to by the path) in tests where we need per-netns managers.

type resolveOpener struct {
	managerByFile map[string]*fakeQdiscManager
	current       string
	mu            interface{ Lock(); Unlock() }
}

func (r *resolveOpener) DoInNetns(path string, fn func() error) error {
	// Resolve symlink so we get the canonical "_netns_files/nsX" path.
	real, err := filepath.EvalSymlinks(path)
	if err != nil {
		real = path // fall back to literal path
	}
	r.current = real
	return fn()
}

func (r *resolveOpener) factory() QdiscManagerFactory {
	return func() QdiscManager {
		mgr, ok := r.managerByFile[r.current]
		if !ok {
			return &fakeQdiscManager{links: nil}
		}
		return mgr
	}
}
