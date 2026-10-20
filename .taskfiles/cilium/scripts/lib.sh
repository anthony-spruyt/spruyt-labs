#!/bin/bash

# Runs the hubble CLI against Hubble Relay so queries cover every node.
# The agent is hostNetwork and can't resolve service DNS, so the relay ClusterIP is passed.
hubble_relay() {
  local relay
  relay=$(kubectl -n kube-system get svc hubble-relay -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')
  if [[ "$1" == observe ]]; then
    set -- "$@" --print-node-name
  fi
  kubectl exec -n kube-system ds/cilium -c cilium-agent -- hubble "$@" --server "$relay"
}
