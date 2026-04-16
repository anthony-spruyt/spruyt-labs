package main

import "testing"

func TestIsPodNetnsName(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want bool
	}{
		{"valid cni uuid", "cni-a88041e9-8a3c-709c-33a7-ab057b2595c0", true},
		{"valid short", "cni-abc123", true},
		{"missing cni prefix", "a88041e9", false},
		{"traversal attempt", "cni-../../etc", false},
		{"absolute path", "/run/netns/cni-abc", false},
		{"empty", "", false},
		{"uppercase hex rejected", "cni-ABCDEF", false},
		{"non-hex chars", "cni-xyz!!!", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := IsPodNetnsName(tc.in); got != tc.want {
				t.Fatalf("IsPodNetnsName(%q) = %v, want %v", tc.in, got, tc.want)
			}
		})
	}
}

func TestIsKataTapDevice(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want bool
	}{
		{"exact match", "tap0_kata", true},
		{"double digit", "tap10_kata", true},
		{"missing digit", "tap_kata", false},
		{"wrong suffix", "tap0_qemu", false},
		{"prefix only", "tap0", false},
		{"embedded", "xtap0_kata", false},
		{"trailing", "tap0_katax", false},
		{"empty", "", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := IsKataTapDevice(tc.in); got != tc.want {
				t.Fatalf("IsKataTapDevice(%q) = %v, want %v", tc.in, got, tc.want)
			}
		})
	}
}
