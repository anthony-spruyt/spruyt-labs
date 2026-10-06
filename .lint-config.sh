#!/usr/bin/env bash
# shellcheck disable=SC2034 # Variables used by sourcing script (lint.sh)
# This file is automatically updated - do not modify directly
# The image pin lives in repo-operator (src/groups.yaml, or src/repos.yaml for a per-repo flavor), where Renovate bumps it

MEGALINTER_IMAGE="ghcr.io/anthony-spruyt/megalinter-spruyt-labs:v2.0.4@sha256:e9267e114872589798c8c98137ce5971ef7b5a93afa5bb615a10df0d9c638c86"

SKIP_BOT_COMMITS=false

# MegaLinter flavor (use "all" for custom images to bypass flavor validation)
MEGALINTER_FLAVOR="all"
