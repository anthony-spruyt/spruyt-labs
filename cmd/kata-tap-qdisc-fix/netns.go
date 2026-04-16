package main

import (
	"errors"
	"fmt"
	"runtime"
	"sync"

	vnetns "github.com/vishvananda/netns"
)

// NetnsOpener abstracts "run fn inside a target netns" so tests can inject
// a fake that runs fn in the caller's netns.
type NetnsOpener interface {
	DoInNetns(path string, fn func() error) error
}

// hostNetns is captured once at main() start and reused for restores.
var (
	hostNetnsOnce sync.Once
	hostNetns     vnetns.NsHandle
	hostNetnsErr  error
)

// InitHostNetns MUST be called from the main goroutine BEFORE any worker
// spawns. It records the current netns as the canonical host netns used
// for all subsequent restores in DoInNetns.
func InitHostNetns() error {
	hostNetnsOnce.Do(func() {
		hostNetns, hostNetnsErr = vnetns.Get()
	})
	return hostNetnsErr
}

type realNetnsOpener struct{}

func NewNetnsOpener() NetnsOpener { return realNetnsOpener{} }

// ErrNetnsRestoreFailed is returned when the daemon entered a target netns
// but failed to restore the host netns. Callers MUST treat this as fatal
// for the calling goroutine — the OS thread is in an inconsistent state.
// The worker supervisor in watcher.go responds by incrementing
// kata_tap_qdisc_thread_retired_total, logging loudly, and calling
// runtime.Goexit() so the Go runtime retires the locked thread rather
// than reusing it for another goroutine.
var ErrNetnsRestoreFailed = errors.New("netns restore failed; thread is poisoned")

func (realNetnsOpener) DoInNetns(path string, fn func() error) (retErr error) {
	if !hostNetns.IsOpen() {
		return fmt.Errorf("host netns not initialised; call InitHostNetns() from main before spawning workers")
	}

	runtime.LockOSThread()
	// Deferred restore — runs even if fn panics. If restore fails we return
	// ErrNetnsRestoreFailed without unlocking the thread; the caller in
	// watcher.process handles retirement (see watcher.go).
	unlock := true
	defer func() {
		if setErr := vnetns.Set(hostNetns); setErr != nil {
			restoreErr := fmt.Errorf("%w: %v", ErrNetnsRestoreFailed, setErr)
			if retErr == nil {
				retErr = restoreErr
			} else {
				retErr = fmt.Errorf("%w (also fn err: %v)", restoreErr, retErr)
			}
			unlock = false
		}
		if unlock {
			runtime.UnlockOSThread()
		}
	}()

	target, err := vnetns.GetFromPath(path)
	if err != nil {
		return fmt.Errorf("get netns from %s: %w", path, err)
	}
	defer target.Close()

	if err := vnetns.Set(target); err != nil {
		return fmt.Errorf("enter netns %s: %w", path, err)
	}
	return fn()
}
