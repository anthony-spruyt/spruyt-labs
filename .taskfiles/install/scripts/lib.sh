#!/bin/bash

# Exits the calling script when the installed version equals the pinned one.
# A leading "v" is ignored on both sides since tools disagree on printing it.
skip_if_installed() {
  local name="$1" pinned="$2" installed="$3"
  if [[ -n "${installed}" && "${installed#v}" == "${pinned#v}" ]]; then
    echo "✅ ${name} ${pinned} already installed, skipping."
    exit 0
  fi
}
