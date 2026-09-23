#!/usr/bin/env bats
#
# Provenance checks for third-party image bumps. Ref #3084

REPO_ROOT="${BATS_TEST_DIRNAME}/.."
SCRIPT="${REPO_ROOT}/.github/scripts/verify-image-provenance.sh"

setup() {
  TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/provenance.XXXXXX")"
  export PROVENANCE_ALLOWLIST="${TMP}/allowlist.txt"
  : >"${PROVENANCE_ALLOWLIST}"
  export PROVENANCE_OFFLINE_FIXTURE="${TMP}/fixture.json"
}

teardown() {
  rm -rf "${TMP}"
}

fixture() {
  cat >"${PROVENANCE_OFFLINE_FIXTURE}"
}

@test "extracts image references from a helm values file" {
  local values="${TMP}/values.yaml"
  cat >"${values}" <<'YAML'
image:
  repository: ghcr.io/berriai/litellm-non_root
  tag: v1.102.1@sha256:aaaa
YAML

  run "${SCRIPT}" --list-refs "${values}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghcr.io/berriai/litellm-non_root:v1.102.1@sha256:aaaa"* ]]
}

@test "extracts inline image references from a manifest" {
  local manifest="${TMP}/deploy.yaml"
  cat >"${manifest}" <<'YAML'
spec:
  containers:
    - image: docker.io/traefik/whoami:v1.2.3@sha256:bbbb
YAML

  run "${SCRIPT}" --list-refs "${manifest}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker.io/traefik/whoami:v1.2.3@sha256:bbbb"* ]]
}

@test "passes when the build commit is reachable upstream" {
  fixture <<'JSON'
{
  "source": "https://github.com/BerriAI/litellm",
  "revision": "d09bbae1c6df463e425558f60d460437193635da",
  "repo_exists": true,
  "commit_exists": true,
  "branches": ["stable/1.102.x"],
  "built_at": "2026-09-23T04:05:16Z",
  "committed_at": "2026-09-23T03:04:11Z"
}
JSON

  run "${SCRIPT}" --verify ghcr.io/berriai/litellm-non_root:v1.102.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERIFIED"* ]]
}

@test "fails when the build commit does not exist upstream" {
  fixture <<'JSON'
{
  "source": "https://github.com/BerriAI/litellm",
  "revision": "0000000000000000000000000000000000000000",
  "repo_exists": true,
  "commit_exists": false,
  "branches": [],
  "built_at": "2026-09-23T04:05:16Z",
  "committed_at": ""
}
JSON

  run "${SCRIPT}" --verify ghcr.io/berriai/litellm-non_root:v9.9.9
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAILED"* ]]
}

@test "fails when the build commit is not reachable from any branch" {
  fixture <<'JSON'
{
  "source": "https://github.com/BerriAI/litellm",
  "revision": "d09bbae1c6df463e425558f60d460437193635da",
  "repo_exists": true,
  "commit_exists": true,
  "branches": [],
  "built_at": "2026-09-23T04:05:16Z",
  "committed_at": "2026-09-23T03:04:11Z"
}
JSON

  run "${SCRIPT}" --verify ghcr.io/berriai/litellm-non_root:v9.9.9
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAILED"* ]]
  [[ "$output" == *"not reachable"* ]]
}

@test "fails when the image was built before its source commit" {
  fixture <<'JSON'
{
  "source": "https://github.com/BerriAI/litellm",
  "revision": "d09bbae1c6df463e425558f60d460437193635da",
  "repo_exists": true,
  "commit_exists": true,
  "branches": ["stable/1.102.x"],
  "built_at": "2026-09-20T00:00:00Z",
  "committed_at": "2026-09-23T03:04:11Z"
}
JSON

  run "${SCRIPT}" --verify ghcr.io/berriai/litellm-non_root:v9.9.9
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAILED"* ]]
  [[ "$output" == *"predates"* ]]
}

@test "does not pair a repository with an unrelated tag key" {
  local values="${TMP}/mispair.yaml"
  cat >"${values}" <<'YAML'
image:
  repository: ghcr.io/example/first
  pullPolicy: IfNotPresent
chart:
  tag: v9.9.9
YAML

  run "${SCRIPT}" --list-refs "${values}"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ghcr.io/example/first:v9.9.9"* ]]
}

@test "pairs repository and tag across sibling image blocks" {
  local values="${TMP}/siblings.yaml"
  cat >"${values}" <<'YAML'
image:
  repository: ghcr.io/example/first
  tag: v1.0.0
sidecar:
  image:
    repository: ghcr.io/example/second
    tag: v2.0.0
YAML

  run "${SCRIPT}" --list-refs "${values}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghcr.io/example/first:v1.0.0"* ]]
  [[ "$output" == *"ghcr.io/example/second:v2.0.0"* ]]
}

@test "a tag that does not resolve fails even when the repo is allowlisted" {
  unset PROVENANCE_OFFLINE_FIXTURE
  echo "docker.io/library/busybox" >"${PROVENANCE_ALLOWLIST}"

  run "${SCRIPT}" --verify docker.io/library/busybox:9.9.9-definitely-not-real
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAILED"* ]]
  [[ "$output" != *"UNVERIFIABLE"* ]]
}

@test "a registry that serves no token endpoint does not leak a parse error" {
  unset PROVENANCE_OFFLINE_FIXTURE
  echo "registry.k8s.io/sig-storage/csi-snapshotter" >"${PROVENANCE_ALLOWLIST}"

  run "${SCRIPT}" --verify registry.k8s.io/sig-storage/csi-snapshotter:v8.6.0
  [[ "$output" != *"parse error"* ]]
  [[ "$output" != *"jq:"* ]]
}

@test "prefers the SLSA build time over the image created label" {
  fixture <<'JSON'
{
  "source": "https://github.com/home-operations/containers",
  "revision": "39495432e084f78ec700d3c0ccac58f47ae8f5e8",
  "repo_exists": true,
  "commit_exists": true,
  "branches": ["main"],
  "built_at": "2026-06-22T17:48:33Z",
  "slsa_built_at": "2026-06-29T12:39:11Z",
  "committed_at": "2026-06-29T12:38:22Z"
}
JSON

  run "${SCRIPT}" --verify ghcr.io/home-operations/irqbalance:1.9.5
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERIFIED"* ]]
}

@test "reports unverifiable for an allowlisted image with no provenance" {
  echo "quay.io/csiaddons/k8s-sidecar" >"${PROVENANCE_ALLOWLIST}"
  fixture <<'JSON'
{
  "source": "",
  "revision": "",
  "repo_exists": false,
  "commit_exists": false,
  "branches": [],
  "built_at": "",
  "committed_at": ""
}
JSON

  run "${SCRIPT}" --verify quay.io/csiaddons/k8s-sidecar:v0.1.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNVERIFIABLE"* ]]
}

@test "fails for a non-allowlisted image with no provenance" {
  fixture <<'JSON'
{
  "source": "",
  "revision": "",
  "repo_exists": false,
  "commit_exists": false,
  "branches": [],
  "built_at": "",
  "committed_at": ""
}
JSON

  run "${SCRIPT}" --verify ghcr.io/someone/mystery:v1.0.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAILED"* ]]
}

@test "allowlist comments and blank lines are ignored" {
  cat >"${PROVENANCE_ALLOWLIST}" <<'LIST'
# no provenance published upstream
quay.io/csiaddons/k8s-sidecar

LIST
  fixture <<'JSON'
{
  "source": "",
  "revision": "",
  "repo_exists": false,
  "commit_exists": false,
  "branches": [],
  "built_at": "",
  "committed_at": ""
}
JSON

  run "${SCRIPT}" --verify quay.io/csiaddons/k8s-sidecar:v0.1.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNVERIFIABLE"* ]]
}
