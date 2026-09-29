#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${CLUSTER_VALIDATOR_LOCK_DIR:-/tmp/cluster-validator}"
LOCK="$STATE_DIR/lock"
RESULT="$STATE_DIR/last-result"
STALE_S="${CLUSTER_VALIDATOR_STALE_S:-1200}"
RESULT_MAX_AGE_S="${CLUSTER_VALIDATOR_RESULT_MAX_AGE_S:-1800}"
POLL_S="${CLUSTER_VALIDATOR_POLL_S:-15}"

usage() {
  cat >&2 <<'EOF'
Usage: cluster-validator-lock.sh <command> [args]
  acquire <sha>                  exit 0 = you own the run, 1 = another session holds it
  release                        drop the lock
  wait [timeout_s]               block until lock is free; exit 2 on timeout (default 1500s)
  record <sha> <verdict> [text]  save result of a completed run
  covered <sha>                  exit 0 + print result if a recent run covered <sha>
  status                         show lock holder and last result
EOF
  exit 64
}

age_s() {
  echo $(($(date +%s) - $(stat -c %Y "$1")))
}

clear_stale() {
  if [ -d "$LOCK" ] && [ "$(age_s "$LOCK")" -ge "$STALE_S" ]; then
    echo "Removing stale lock: $(cat "$LOCK/owner" 2>/dev/null || echo unknown)" >&2
    rm -rf "$LOCK"
  fi
}

cmd="${1:-}"
[ -n "$cmd" ] || usage
shift
mkdir -p "$STATE_DIR"

case "$cmd" in
acquire)
  [ $# -ge 1 ] || usage
  clear_stale
  if mkdir "$LOCK" 2>/dev/null; then
    echo "sha=$1 pid=$PPID cwd=$PWD started=$(date -u +%FT%TZ)" >"$LOCK/owner"
    echo "Lock acquired"
    exit 0
  fi
  echo "Lock held: $(cat "$LOCK/owner" 2>/dev/null || echo unknown)"
  exit 1
  ;;
release)
  rm -rf "$LOCK"
  echo "Lock released"
  ;;
wait)
  timeout="${1:-1500}"
  deadline=$(($(date +%s) + timeout))
  while clear_stale && [ -d "$LOCK" ]; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "Timed out waiting for lock: $(cat "$LOCK/owner" 2>/dev/null || echo unknown)"
      exit 2
    fi
    sleep "$POLL_S"
  done
  echo "Lock free"
  ;;
record)
  [ $# -ge 2 ] || usage
  tmp="$(mktemp "$STATE_DIR/result.XXXXXX")"
  {
    echo "sha=$1"
    echo "verdict=$2"
    echo "finished=$(date -u +%FT%TZ)"
    echo "summary=${3:-}"
  } >"$tmp"
  mv "$tmp" "$RESULT"
  echo "Result recorded"
  ;;
covered)
  [ $# -ge 1 ] || usage
  [ -f "$RESULT" ] || exit 1
  [ "$(age_s "$RESULT")" -lt "$RESULT_MAX_AGE_S" ] || exit 1
  recorded="$(sed -n 's/^sha=//p' "$RESULT")"
  git merge-base --is-ancestor "$1" "$recorded" 2>/dev/null || exit 1
  cat "$RESULT"
  ;;
status)
  if [ -d "$LOCK" ]; then
    echo "lock: held ($(age_s "$LOCK")s) $(cat "$LOCK/owner" 2>/dev/null || true)"
  else
    echo "lock: free"
  fi
  if [ -f "$RESULT" ]; then
    echo "last result ($(age_s "$RESULT")s ago):"
    cat "$RESULT"
  fi
  ;;
*)
  usage
  ;;
esac
