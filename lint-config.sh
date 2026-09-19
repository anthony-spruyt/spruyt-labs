#!/usr/bin/env bash
# shellcheck disable=SC2034 # Variables used by sourcing script (lint.sh)
# Lint configuration - customize per repository
# This file is sourced by lint.sh for both local and CI runs

# MegaLinter Docker image (use digest for reproducibility)
# renovate: datasource=docker depName=ghcr.io/anthony-spruyt/megalinter-spruyt-labs
MEGALINTER_IMAGE="ghcr.io/anthony-spruyt/megalinter-spruyt-labs:v2.0.0@sha256:95d5a076919b3dc5057ed1a029afea025cd82a98771d081ba6203feda5146a32"

# Skip linting for renovate/dependabot commits in CI
SKIP_BOT_COMMITS=false

# MegaLinter flavor (use "all" for custom images to bypass flavor validation)
MEGALINTER_FLAVOR="all"
