#!/usr/bin/env bash
# Kata podman probe harness for #977
set -euo pipefail

PROBE="${1:-}"
[[ -z "${PROBE}" ]] && {
  echo "usage: $0 <probe-number>" >&2
  exit 2
}

MANIFEST="$(dirname "$0")/manifests/probe-${PROBE}.yaml"
[[ ! -f "${MANIFEST}" ]] && {
  echo "no manifest: ${MANIFEST}" >&2
  exit 2
}

POD="kata-podman-probe-${PROBE}-$(date +%s)"
NS="default"

# shellcheck disable=SC2064
trap "kubectl -n ${NS} delete pod ${POD} --ignore-not-found --wait=false" EXIT

sed "s|__POD_NAME__|${POD}|g" "${MANIFEST}" | kubectl -n "${NS}" apply -f -

kubectl -n "${NS}" wait --for=condition=Ready "pod/${POD}" --timeout=120s

echo "--- probe ${PROBE} repro ---"
kubectl -n "${NS}" exec "${POD}" -- sh -c '
  dnf -qy install util-linux > /dev/null 2>&1 || true
  # Test: multi-line write to /proc/PID/uid_map with CAP_SETUID in parent userns.
  # Fork a child into a NEW userns that waits; parent writes multi-line uid_map.
  unshare -Ur --kill-child sh -c '"'"'
    sleep 9999 &
    CHILD=$!
    sleep 0.2
    printf "0 0 1\n1 100000 65536\n" > /proc/$CHILD/uid_map 2>&1
    rc=$?
    echo "multi-line uid_map write rc=$rc"
    [ $rc -ne 0 ] && echo "--- uid_map content ---" && cat /proc/$CHILD/uid_map
    kill $CHILD 2>/dev/null
    exit $rc
  '"'"'
'
echo "--- probe ${PROBE} dmesg tail ---"
kubectl -n "${NS}" exec "${POD}" -- sh -c 'dmesg 2>/dev/null | tail -20 || echo "(dmesg unavailable)"'
