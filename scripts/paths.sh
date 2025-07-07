#!/bin/bash
set -euo pipefail

TALOS_OUTPUT_PATH="${PROJECT_ROOT_ABS}/talos/config"
TALOS_PATCHES_PATH="${PROJECT_ROOT_ABS}/talos/patches"
TALOS_SECRETS_PATH="${PROJECT_ROOT_ABS}/secrets/talos.yaml"
CILIUM_VALUES_PATH="${PROJECT_ROOT_ABS}/cluster/infrastructure/controllers/cilium/cilium-values.yaml"
FLUX_PATH="${PROJECT_ROOT_ABS}/cluster"
FLUX_TEST_PATH="${PROJECT_ROOT_ABS}/flux"