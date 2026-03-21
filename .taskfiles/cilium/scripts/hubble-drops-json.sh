#!/bin/bash
set -euo pipefail

# Show drops with full JSON detail (for debugging policy issues)
kubectl exec -n kube-system ds/cilium -- hubble observe --verdict DROPPED --last 50 -o json |
  jq -r '. | {time: .time, src: (.source.namespace + "/" + .source.pod_name), dst: (.destination.namespace + "/" + .destination.pod_name), port: (.l4.TCP.destination_port // .l4.UDP.destination_port), drop_reason: .drop_reason_desc, policy: .policy_match_type}'
