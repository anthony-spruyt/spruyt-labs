#!/bin/bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hubble_relay observe --verdict DROPPED --last 50 -o json |
  jq -r 'select(.flow) | .flow as $f | {time: .time, node: .node_name, src: (if $f.source.pod_name then $f.source.namespace + "/" + $f.source.pod_name else $f.IP.source end), dst: (if $f.destination.pod_name then $f.destination.namespace + "/" + $f.destination.pod_name else $f.IP.destination end), port: ($f.l4.TCP.destination_port // $f.l4.UDP.destination_port), drop_reason: $f.drop_reason_desc, policy: $f.policy_match_type}'
