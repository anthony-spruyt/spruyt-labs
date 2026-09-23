#!/usr/bin/env bats
#
# Provenance checks for third-party image bumps. Ref #3084
# shellcheck disable=SC1090,SC2329  # tests source the script and shadow its functions with mocks

REPO_ROOT="${BATS_TEST_DIRNAME}/.."
SCRIPT="${REPO_ROOT}/.taskfiles/test/scripts/verify-image-provenance.sh"

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
  source "${SCRIPT}"
  registry_token() { echo; }
  fetch_status() { echo 404; }
  export -f registry_token fetch_status

  run verify docker.io/library/busybox:9.9.9-definitely-not-real
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

@test "normalizes docker hub short names to a fully qualified reference" {
  local values="${TMP}/short.yaml"
  cat >"${values}" <<'YAML'
image:
  repository: busybox
  tag: 1.38.0@sha256:cccc
sidecar:
  image: n8nio/n8n:2.38.7
YAML

  run "${SCRIPT}" --list-refs "${values}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker.io/library/busybox:1.38.0@sha256:cccc"* ]]
  [[ "$output" == *"docker.io/n8nio/n8n:2.38.7"* ]]
  [[ "$output" != *$'\nbusybox:'* ]]
}

@test "pairs kustomize image overrides and skips tagless inline references" {
  local release="${TMP}/release.yaml"
  cat >"${release}" <<'YAML'
postRenderers:
  - kustomize:
      images:
        - name: n8nio/runners
          newTag: "2.38.7"
      patches:
        - patch: |-
            containers:
              - name: task-runner
                image: n8nio/runners
YAML

  run "${SCRIPT}" --list-refs "${release}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker.io/n8nio/runners:2.38.7"* ]]
  [[ "$output" != *"runners:n8nio"* ]]
  [ "$(printf '%s\n' "$output" | grep -c runners)" -eq 1 ]
}

@test "passes when the build commit is reachable only from a tag" {
  fixture <<'JSON'
{
  "source": "https://github.com/temporalio/temporal",
  "revision": "d94e34a1ebba5410a2e7d07119a76896909591aa",
  "repo_exists": true,
  "commit_exists": true,
  "branches": [],
  "tags": ["v1.32.0"],
  "built_at": "2026-09-12T00:00:00Z",
  "committed_at": "2026-09-11T00:21:46Z"
}
JSON

  run "${SCRIPT}" --verify docker.io/temporalio/server:1.32.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERIFIED"* ]]
  [[ "$output" == *"v1.32.0"* ]]
}

@test "accepts ssh style github source urls" {
  source "${SCRIPT}"
  [ "$(github_slug 'git@github.com:sonatype/docker-nexus3.git')" = "sonatype/docker-nexus3" ]
  [ "$(github_slug 'ssh://git@github.com/sonatype/docker-nexus3')" = "sonatype/docker-nexus3" ]
  [ "$(github_slug 'https://github.com/BerriAI/litellm.git')" = "BerriAI/litellm" ]
  run github_slug 'https://gitlab.com/org/repo'
  [ "$status" -eq 1 ]
}

@test "caps branch comparisons for a commit that is not a branch head" {
  export PROVENANCE_MAX_COMPARES=3
  source "${SCRIPT}"
  local calls="${TMP}/calls"
  : >"${calls}"
  gh() {
    case "$2" in
    */branches-where-head) return 1 ;;
    */tags*) echo '[]' ;;
    repos/org/repo) echo main ;;
    */branches*) printf 'b%s\n' 1 2 3 4 5 6 7 8 9 10 ;;
    */compare/*)
      echo "$2" >>"${calls}"
      echo diverged
      ;;
    esac
  }
  export -f gh

  run reachable_refs org/repo deadbeef
  [ "$status" -eq 0 ]
  [ "$(wc -l <"${calls}")" -le 3 ]
}

@test "finds a tag whose commit matches the build revision" {
  source "${SCRIPT}"
  gh() {
    case "$2" in
    */branches-where-head) return 1 ;;
    */tags*) echo '[{"name":"v1.32.0","commit":{"sha":"d94e34a"}},{"name":"v1.31.0","commit":{"sha":"abc"}}]' ;;
    *) return 1 ;;
    esac
  }
  export -f gh

  run reachable_refs temporalio/temporal d94e34a
  [ "$status" -eq 0 ]
  [ "$(jq -r '.tags | join(",")' <<<"$output")" = "v1.32.0" ]
  [ "$(jq -r '.branches | length' <<<"$output")" -eq 0 ]
}

@test "a source outside github is unverifiable, not missing" {
  echo "docker.io/arcadiatechnology/crafty-4" >"${PROVENANCE_ALLOWLIST}"
  fixture <<'JSON'
{
  "source": "https://gitlab.com/crafty-controller/crafty-4",
  "revision": "abc123",
  "repo_exists": false,
  "commit_exists": false,
  "branches": [],
  "built_at": "",
  "committed_at": ""
}
JSON

  run "${SCRIPT}" --verify docker.io/arcadiatechnology/crafty-4:4.10.8
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNVERIFIABLE"* ]]
  [[ "$output" == *"gitlab.com"* ]]

  : >"${PROVENANCE_ALLOWLIST}"
  run "${SCRIPT}" --verify docker.io/arcadiatechnology/crafty-4:4.10.8
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAILED"* ]]
  [[ "$output" != *"does not exist"* ]]
}

@test "a registry rate limit is unverifiable, not failed" {
  unset PROVENANCE_OFFLINE_FIXTURE
  source "${SCRIPT}"
  registry_token() { echo; }
  fetch_status() { echo 429; }
  export -f registry_token fetch_status

  run fetch_registry_facts docker.io/library/busybox:1.38.0
  [ "$status" -eq 3 ]

  fetch_registry_facts() { return 3; }
  export -f fetch_registry_facts
  run verify docker.io/library/busybox:1.38.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNVERIFIABLE"* ]]
  [[ "$output" == *"rate limited"* ]]
}

@test "the image index is fetched once and reused for the attestation lookup" {
  unset PROVENANCE_OFFLINE_FIXTURE
  source "${SCRIPT}"
  local calls="${TMP}/calls"
  : >"${calls}"
  registry_token() { echo; }
  fetch_status() {
    echo "$1" >>"${calls}"
    echo '{"manifests":[{"digest":"sha256:amd","platform":{"architecture":"amd64","os":"linux"}}]}' >"$2"
    echo 200
  }
  fetch() {
    local url="${*: -1}"
    echo "${url}" >>"${calls}"
    case "${url}" in
    */manifests/sha256:amd) echo '{"config":{"digest":"sha256:cfg"}}' ;;
    */blobs/sha256:cfg) echo '{"config":{"Labels":{}},"created":""}' ;;
    *) return 22 ;;
    esac
  }
  export -f registry_token fetch_status fetch

  run fetch_registry_facts docker.io/library/busybox:1.38.0
  [ "$status" -eq 0 ]
  [ "$(grep -c 'manifests/1.38.0' "${calls}")" -eq 1 ]
}

@test "kustomize newName overrides the image name" {
  local release="${TMP}/rename.yaml"
  cat >"${release}" <<'YAML'
images:
  - name: n8nio/runners
    newName: ghcr.io/mirror/runners
    newTag: "2.38.7"
YAML

  run "${SCRIPT}" --list-refs "${release}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghcr.io/mirror/runners:2.38.7"* ]]
  [[ "$output" != *"n8nio/runners"* ]]
}
