#!/bin/bash
# Resolves cluster and node configuration from live cluster state.
# Works in both Coder workspace and local devcontainer — no gitignored config needed.

resolve_cluster_name() {
  talosctl config info 2>/dev/null | awk '/Current context:/{print $NF}'
}

resolve_node_ip() {
  local hostname="$1"
  local ip
  ip=$(kubectl get node "${hostname}" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
  if [[ -z "${ip}" ]]; then
    echo "ERROR: could not resolve IP for node '${hostname}'" >&2
    return 1
  fi
  echo "${ip}"
}
