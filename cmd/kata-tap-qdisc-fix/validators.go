package main

import "regexp"

var (
	podNetnsNameRE  = regexp.MustCompile(`^cni-[0-9a-f][0-9a-f-]*$`)
	kataTapDeviceRE = regexp.MustCompile(`^tap[0-9]+_kata$`)
)

// IsPodNetnsName reports whether name is a safe CNI-generated pod network
// namespace filename (as seen under /run/netns).
func IsPodNetnsName(name string) bool {
	return podNetnsNameRE.MatchString(name)
}

// IsKataTapDevice reports whether ifname is a Kata CLH tap device
// (tap<N>_kata where N is an unsigned integer).
func IsKataTapDevice(ifname string) bool {
	return kataTapDeviceRE.MatchString(ifname)
}
