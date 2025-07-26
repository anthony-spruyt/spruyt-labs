#!/bin/bash
#set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

#kubectl drain ${C3_HOST} --ignore-daemonsets --delete-emptydir-data
#kubectl delete node ${C3_HOST}
talosctl reset -n ${C3_IP}
#kubectl drain ${C2_HOST} --ignore-daemonsets --delete-emptydir-data
#kubectl delete node ${C2_HOST}
talosctl reset -n ${C2_IP}
#kubectl drain ${C1_HOST} --ignore-daemonsets --delete-emptydir-data
#kubectl delete node ${C1_HOST}
talosctl reset -n ${C1_IP}
