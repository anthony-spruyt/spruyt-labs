#!/usr/bin/env bash
set -euo pipefail

NS=dev-debug
MANIFEST="$(dirname "$0")/manifest.yaml"

trap '
  kubectl -n '"${NS}"' delete -f '"${MANIFEST}"' --ignore-not-found --wait=false
' EXIT

kubectl -n "${NS}" apply -f "${MANIFEST}"
kubectl -n "${NS}" wait --for=condition=Ready pod/kata-fuse-probe --timeout=120s

echo "--- /dev/fuse ---"
kubectl -n "${NS}" exec kata-fuse-probe -- sh -c 'ls -l /dev/fuse 2>&1; echo rc=$?'
echo "--- /dev/net/tun ---"
kubectl -n "${NS}" exec kata-fuse-probe -- sh -c 'ls -l /dev/net/tun 2>&1; echo rc=$?'
echo "--- fuse-overlayfs smoketest ---"
kubectl -n "${NS}" exec kata-fuse-probe -- sh -c '
  dnf -qy install fuse-overlayfs fuse > /dev/null 2>&1
  mkdir -p /tmp/{lower,upper,work,merged}
  fuse-overlayfs -o lowerdir=/tmp/lower,upperdir=/tmp/upper,workdir=/tmp/work /tmp/merged 2>&1
  echo rc=$?
  mountpoint /tmp/merged 2>&1
'
