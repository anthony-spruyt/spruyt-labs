#!/bin/sh
# Multi-module golangci-lint wrapper for MegaLinter.
# MegaLinter invokes this once per .go file. The wrapper finds the
# enclosing Go module, lints it once, and caches the result so
# subsequent .go files in the same module are no-ops.
# Note: MegaLinter args ($@) are intentionally not forwarded;
# the wrapper controls golangci-lint invocation directly.
set -eu
export GOMODCACHE=/tmp/gomod GOPATH=/tmp/gopath GOTOOLCHAIN=auto
WS="${DEFAULT_WORKSPACE:-/tmp/lint}"
CACHE_DIR="/tmp/golangci-lint-done"
mkdir -p "$CACHE_DIR"

# Handle version queries from MegaLinter
case "${1:-}" in
--version | -version | version)
  golangci-lint version
  exit $?
  ;;
esac

# MegaLinter passes: run --fix -c <config> <filepath>.go
# Extract the last argument (the actual .go file path)
target=""
for _arg in "$@"; do target="$_arg"; done
if [ -z "$target" ] || [ "${target%.go}" = "$target" ]; then
  exit 0
fi
dir="$(cd "$(dirname "$target")" && pwd)" || exit 0
modroot=""
while [ "$dir" != "/" ] && [ -n "$dir" ]; do
  if [ -f "$dir/go.mod" ]; then
    modroot="$dir"
    break
  fi
  dir="$(dirname "$dir")"
done
if [ -z "$modroot" ]; then
  echo "No go.mod found for $target, skipping"
  exit 0
fi

# Cache key: hash of module path
cache_key="$(echo "$modroot" | md5sum | cut -d' ' -f1)"
if [ -f "$CACHE_DIR/$cache_key" ]; then
  cached_rc="$(cat "$CACHE_DIR/$cache_key")"
  exit "$cached_rc"
fi

# Run golangci-lint for this module
echo "golangci-lint: $modroot"
cd "$modroot" || exit 1
golangci-lint run --config "$WS/.golangci.yml" ./...
rc=$?
printf '%s' "$rc" >"$CACHE_DIR/$cache_key"
exit $rc
