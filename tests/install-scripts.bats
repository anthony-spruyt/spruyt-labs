#!/usr/bin/env bats
#
# Pinned install scripts skip the download when that exact version is installed. Ref #3266

SCRIPTS="${BATS_TEST_DIRNAME}/../.taskfiles/install/scripts"

setup() {
  BIN="$(mktemp -d)"
  # Installers reach the network through these, so a skip never prints CALLED.
  printf '#!/bin/bash\necho CURL_CALLED\nexit 1\n' >"${BIN}/curl"
  printf '#!/bin/bash\nexit 0\n' >"${BIN}/sudo"
  printf '#!/bin/bash\necho GO_INSTALL_CALLED\n' >"${BIN}/go"
  chmod +x "${BIN}"/*
  # /usr/local/bin and the node/go toolchains are left out so real tools never answer.
  export PATH="${BIN}:/usr/bin:/bin"
}

teardown() {
  rm -rf "${BIN}"
}

pinned() {
  sed -n 's/^VERSION="\(.*\)"$/\1/p' "${SCRIPTS}/install-$1.sh"
}

stub() {
  printf '%b\n' "$2" >"${BIN}/$1.out"
  printf '#!/bin/bash\ncat "%s"\n' "${BIN}/$1.out" >"${BIN}/$1"
  chmod +x "${BIN}/$1"
}

expect_skip() {
  run bash "${SCRIPTS}/install-$1.sh"
  [ "${status}" -eq 0 ] || {
    echo "install-$1.sh exited ${status}: ${output}" >&2
    return 1
  }
  [[ "${output}" == *"already installed"* && "${output}" != *CALLED* ]] || {
    echo "install-$1.sh did not skip: ${output}" >&2
    return 1
  }
}

expect_install() {
  run bash "${SCRIPTS}/install-$1.sh"
  [[ "${output}" == *CALLED* ]] || {
    echo "install-$1.sh skipped the install: ${output}" >&2
    return 1
  }
}

@test "every script with a pinned VERSION checks the installed version" {
  local script missing=""
  for script in "${SCRIPTS}"/install-*.sh; do
    grep -q '^VERSION=' "${script}" || continue
    grep -q 'skip_if_installed ' "${script}" || missing+=" $(basename "${script}")"
  done
  [ -z "${missing}" ] || {
    echo "no skip_if_installed in:${missing}" >&2
    return 1
  }
}

@test "kubectl skips only at the pinned version" {
  local v
  v="$(pinned kubectl)"
  stub kubectl "Client Version: ${v}\nKustomize Version: v5.8.1"
  expect_skip kubectl
  stub kubectl "Client Version: ${v}0\nKustomize Version: v5.8.1"
  expect_install kubectl
}

@test "kubectl installs when it is missing" {
  expect_install kubectl
}

@test "kustomize skips only at the pinned version" {
  stub kustomize "$(pinned kustomize)"
  expect_skip kustomize
  stub kustomize "v0.0.1"
  expect_install kustomize
}

@test "helm skips only at the pinned version" {
  stub helm "$(pinned helm)"
  expect_skip helm
  stub helm "v0.0.1"
  expect_install helm
}

@test "helmfile skips only at the pinned version" {
  local v
  v="$(pinned helmfile)"
  stub helmfile "${v#v}"
  expect_skip helmfile
  stub helmfile "0.0.1"
  expect_install helmfile
}

@test "cilium skips only at the pinned version" {
  stub cilium "cilium-cli: $(pinned cilium) compiled with go1.27.1 on linux/amd64\ncilium image (default): v1.20.1"
  expect_skip cilium
  stub cilium "cilium-cli: v0.0.1 compiled with go1.27.1 on linux/amd64\ncilium image (default): $(pinned cilium)"
  expect_install cilium
}

@test "hubble skips only at the pinned version" {
  stub hubble "hubble $(pinned hubble)@HEAD-39037bd compiled with go1.26.4 on linux/amd64"
  expect_skip hubble
  stub hubble "hubble v0.0.1@HEAD-39037bd compiled with go1.26.4 on linux/amd64"
  expect_install hubble
}

@test "topf skips only at the pinned version" {
  local v
  v="$(pinned topf)"
  stub topf "topf version ${v#v} (Talos v1.14.0)"
  expect_skip topf
  stub topf "topf version 0.0.1 (Talos v1.14.0)"
  expect_install topf
}

@test "uv skips only at the pinned version" {
  stub uv "uv $(pinned uv) (x86_64-unknown-linux-gnu)"
  expect_skip uv
  stub uv "uv 0.0.1 (x86_64-unknown-linux-gnu)"
  expect_install uv
}

@test "vals skips only at the pinned version" {
  local v
  v="$(pinned vals)"
  stub vals "Version: ${v#v}\nGit Commit: 43e1454"
  expect_skip vals
  stub vals "Version: 0.0.1\nGit Commit: 43e1454"
  expect_install vals
}

@test "velero skips only at the pinned version" {
  stub velero "Client:\n\tVersion: $(pinned velero)\n\tGit commit: cd3fd10"
  expect_skip velero
  stub velero "Client:\n\tVersion: v0.0.1\n\tGit commit: cd3fd10"
  expect_install velero
}

@test "cnpg skips only at the pinned version" {
  local v
  v="$(pinned cnpg)"
  stub kubectl-cnpg "Build: {Version:${v#v} Commit:2a35abb46 Date:2026-09-23}"
  expect_skip cnpg
  stub kubectl-cnpg "Build: {Version:0.0.1 Commit:2a35abb46 Date:2026-09-23}"
  expect_install cnpg
}

@test "falcoctl skips only at the pinned version" {
  local v
  v="$(pinned falcoctl)"
  stub falcoctl "Client Version: ${v#v}"
  expect_skip falcoctl
  stub falcoctl "Client Version: 0.0.1"
  expect_install falcoctl
}

@test "gopls skips only at the pinned version" {
  stub gopls "golang.org/x/tools/gopls $(pinned gopls)"
  expect_skip gopls
  stub gopls "golang.org/x/tools/gopls v0.0.1"
  expect_install gopls
}

@test "cclsp skips only at the pinned version" {
  local v
  v="$(pinned cclsp)"
  printf '#!/bin/bash\nif [ "$1" = ls ]; then echo "└── cclsp@%s"; else echo NPM_INSTALL_CALLED; fi\n' "${v}" >"${BIN}/npm"
  chmod +x "${BIN}/npm"
  expect_skip cclsp
  printf '#!/bin/bash\nif [ "$1" = ls ]; then echo "└── cclsp@0.0.1"; else echo NPM_INSTALL_CALLED; fi\n' >"${BIN}/npm"
  expect_install cclsp
}
