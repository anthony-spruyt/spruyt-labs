#!/usr/bin/env bash
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cluster-validator-lock.sh"
PASS=0
FAIL=0

setup() {
  WORK="$(mktemp -d)"
  export CLUSTER_VALIDATOR_LOCK_DIR="$WORK/state"
  export CLUSTER_VALIDATOR_POLL_S=1
  REPO="$WORK/repo"
  git init -q "$REPO"
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one
  SHA1="$(git -C "$REPO" rev-parse HEAD)"
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m two
  SHA2="$(git -C "$REPO" rev-parse HEAD)"
  cd "$REPO" || exit 1
}

teardown() {
  cd / && rm -rf "$WORK"
}

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $name (expected '$expected', got '$actual')"
  fi
}

run() {
  "$SCRIPT" "$@" >/dev/null 2>&1
  echo $?
}

setup
check "first acquire wins" 0 "$(run acquire "$SHA2")"
check "second acquire loses" 1 "$(run acquire "$SHA2")"
check "release" 0 "$(run release)"
check "acquire after release" 0 "$(run acquire "$SHA2")"
teardown

setup
run acquire "$SHA2" >/dev/null
touch -d "-30 minutes" "$CLUSTER_VALIDATOR_LOCK_DIR/lock"
check "stale lock is taken over" 0 "$(run acquire "$SHA2")"
teardown

setup
run acquire "$SHA2" >/dev/null
check "wait times out while held" 2 "$(run wait 2)"
run release >/dev/null
check "wait returns once free" 0 "$(run wait 2)"
teardown

setup
check "nothing recorded is not covered" 1 "$(run covered "$SHA1")"
run record "$SHA2" PASS "all green" >/dev/null
check "ancestor commit is covered" 0 "$(run covered "$SHA1")"
check "same commit is covered" 0 "$(run covered "$SHA2")"
check "covered prints verdict" "PASS" "$("$SCRIPT" covered "$SHA1" | grep -o PASS | head -1)"
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m three
SHA3="$(git rev-parse HEAD)"
check "newer commit is not covered" 1 "$(run covered "$SHA3")"
teardown

setup
run record "$SHA2" PASS "all green" >/dev/null
touch -d "-60 minutes" "$CLUSTER_VALIDATOR_LOCK_DIR/last-result"
check "old result is not covered" 1 "$(run covered "$SHA1")"
teardown

setup
check "unknown command fails" 64 "$(run bogus)"
teardown

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
