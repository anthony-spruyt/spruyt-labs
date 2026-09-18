#!/usr/bin/env bash
# shellcheck disable=SC2034 # Variables used by sourcing script (lint.sh)
# Lint configuration - customize per repository
# This file is sourced by lint.sh for both local and CI runs

# MegaLinter Docker image (use digest for reproducibility)
# renovate: datasource=docker depName=ghcr.io/anthony-spruyt/megalinter-spruyt-labs
MEGALINTER_IMAGE="ghcr.io/anthony-spruyt/megalinter-spruyt-labs:v1.0.39@sha256:99b411e8ce0d12213f304e5383cfb0f1239844ed9a45956b4ee4f88fe504e15f"

# Skip linting for renovate/dependabot commits in CI
SKIP_BOT_COMMITS=false

# MegaLinter flavor (use "all" for custom images to bypass flavor validation)
MEGALINTER_FLAVOR="all"
