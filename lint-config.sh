#!/usr/bin/env bash
# shellcheck disable=SC2034 # Variables used by sourcing script (lint.sh)
# Lint configuration - customize per repository
# This file is sourced by lint.sh for both local and CI runs

# MegaLinter Docker image (use digest for reproducibility)
# renovate: datasource=docker depName=ghcr.io/anthony-spruyt/megalinter-spruyt-labs
MEGALINTER_IMAGE="ghcr.io/anthony-spruyt/megalinter-spruyt-labs:v2.0.1@sha256:2486ee23ffca39245b09a4bcef4f1d2f1ad5f7b00bc24257f2e96e31df287183"

# Skip linting for renovate/dependabot commits in CI
SKIP_BOT_COMMITS=false

# MegaLinter flavor (use "all" for custom images to bypass flavor validation)
MEGALINTER_FLAVOR="all"
