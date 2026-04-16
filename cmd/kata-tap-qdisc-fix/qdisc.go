package main

import (
	"fmt"

	"github.com/vishvananda/netlink"
)

// LinkInfo is a testable snapshot of a network interface relevant to
// qdisc replacement decisions.
type LinkInfo struct {
	Name          string
	RootQdiscType string
}

// QdiscManager abstracts netlink operations so tests can inject a fake.
type QdiscManager interface {
	ListLinks() ([]LinkInfo, error)
	ReplaceRootWithPfifoFast(dev string) error
}

// QdiscManagerFactory constructs a QdiscManager for a single netns visit.
type QdiscManagerFactory func() QdiscManager

// ReplacementResult reports what ApplyReplacement did (or would have done).
type ReplacementResult struct {
	Replaced     int
	WouldReplace int
	Skipped      int
}

// ApplyReplacement lists all links via m, and for every link whose name
// matches IsKataTapDevice AND whose root qdisc is "fq", replaces the root
// qdisc with pfifo_fast (or counts it in WouldReplace when dryRun is true).
func ApplyReplacement(m QdiscManager, dryRun bool) (ReplacementResult, error) {
	var res ReplacementResult
	links, err := m.ListLinks()
	if err != nil {
		return res, fmt.Errorf("list links: %w", err)
	}
	for _, link := range links {
		if !IsKataTapDevice(link.Name) {
			continue
		}
		if link.RootQdiscType != "fq" {
			res.Skipped++
			continue
		}
		if dryRun {
			res.WouldReplace++
			continue
		}
		if err := m.ReplaceRootWithPfifoFast(link.Name); err != nil {
			return res, fmt.Errorf("replace qdisc on %s: %w", link.Name, err)
		}
		res.Replaced++
	}
	return res, nil
}

// realQdiscManager is the production implementation backed by netlink.
// Must be called with the calling goroutine inside the target netns.
type realQdiscManager struct{}

func NewQdiscManager() QdiscManager { return realQdiscManager{} }

func (realQdiscManager) ListLinks() ([]LinkInfo, error) {
	links, err := netlink.LinkList()
	if err != nil {
		return nil, err
	}
	out := make([]LinkInfo, 0, len(links))
	for _, l := range links {
		root := ""
		qdiscs, qerr := netlink.QdiscList(l)
		if qerr == nil {
			for _, q := range qdiscs {
				if q.Attrs().Parent == netlink.HANDLE_ROOT {
					root = q.Type()
					break
				}
			}
		}
		out = append(out, LinkInfo{Name: l.Attrs().Name, RootQdiscType: root})
	}
	return out, nil
}

func (realQdiscManager) ReplaceRootWithPfifoFast(dev string) error {
	link, err := netlink.LinkByName(dev)
	if err != nil {
		return fmt.Errorf("link by name %s: %w", dev, err)
	}
	q := &netlink.GenericQdisc{
		QdiscAttrs: netlink.QdiscAttrs{
			LinkIndex: link.Attrs().Index,
			Parent:    netlink.HANDLE_ROOT,
		},
		QdiscType: "pfifo_fast",
	}
	return netlink.QdiscReplace(q)
}
