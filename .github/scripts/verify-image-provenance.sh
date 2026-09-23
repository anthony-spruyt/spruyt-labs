#!/usr/bin/env bash
# Verify that a third-party image was built from source that exists upstream. Ref #3084
set -euo pipefail

ALLOWLIST="${PROVENANCE_ALLOWLIST:-$(dirname "${BASH_SOURCE[0]}")/provenance-allowlist.txt}"
CLOCK_SKEW_SECONDS="${PROVENANCE_CLOCK_SKEW:-600}"

die() {
  echo "$*" >&2
  exit 2
}

require() {
  for cmd in "$@"; do
    command -v "${cmd}" >/dev/null || die "${cmd} is required but not installed"
  done
}

# registries redirect to CDNs, so follow only while the scheme stays https
fetch() {
  curl -fsSL --proto '=https' --proto-redir '=https' "$@"
}

registry_token() {
  local host="$1" path="$2" url
  case "${host}" in
  ghcr.io) url="https://ghcr.io/token?service=ghcr.io&scope=repository:${path}:pull" ;;
  docker.io) url="https://auth.docker.io/token?service=registry.docker.io&scope=repository:${path}:pull" ;;
  quay.io) url="https://quay.io/v2/auth?service=quay.io&scope=repository:${path}:pull" ;;
  public.ecr.aws) url="https://public.ecr.aws/token/?service=public.ecr.aws&scope=repository:${path}:pull" ;;
  *) url="https://${host}/v2/token?service=${host}&scope=repository:${path}:pull" ;;
  esac

  fetch "${url}" 2>/dev/null | jq -r '.token // empty' 2>/dev/null
}

registry_host() {
  local host="$1"
  case "${host}" in
  docker.io) echo "registry-1.docker.io" ;;
  *) echo "${host}" ;;
  esac
}

fetch_registry_facts() {
  local ref="$1"
  local without_digest="${ref%%@*}"
  local repo="${without_digest%:*}" tag="${without_digest##*:}"
  local host="${repo%%/*}" path="${repo#*/}"
  local api_host token accept manifest amd64 config source revision built_at

  api_host="$(registry_host "${host}")"
  token="$(registry_token "${host}" "${path}" 2>/dev/null || true)"
  local -a auth=()
  if [[ -n "${token}" ]] && [[ "${token}" != "null" ]]; then
    auth=(-H "Authorization: Bearer ${token}")
  fi

  accept="application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json"
  manifest="$(fetch "${auth[@]+"${auth[@]}"}" -H "Accept: ${accept}" \
    "https://${api_host}/v2/${path}/manifests/${tag}")" || die "image ${ref} does not resolve in the registry"

  amd64="$(jq -r 'if .manifests then (.manifests[] | select(.platform.architecture == "amd64" and .platform.os == "linux") | .digest) else empty end' <<<"${manifest}" | head -1)"
  if [[ -n "${amd64}" ]]; then
    manifest="$(fetch "${auth[@]+"${auth[@]}"}" -H "Accept: ${accept}" \
      "https://${api_host}/v2/${path}/manifests/${amd64}")"
  fi

  config="$(jq -r '.config.digest // empty' <<<"${manifest}")"
  [[ -n "${config}" ]] || die "image ${ref} exposes no config blob"

  local config_json
  config_json="$(fetch "${auth[@]+"${auth[@]}"}" "https://${api_host}/v2/${path}/blobs/${config}")"
  source="$(jq -r '.config.Labels["org.opencontainers.image.source"] // ""' <<<"${config_json}")"
  revision="$(jq -r '.config.Labels["org.opencontainers.image.revision"] // ""' <<<"${config_json}")"
  built_at="$(jq -r '.created // ""' <<<"${config_json}")"

  # Base-image labels survive into the final image, so the SLSA predicate wins
  local slsa slsa_built_at=""
  slsa="$(fetch_slsa_vcs "${api_host}" "${path}" "${tag}" "${amd64}" "${auth[@]+"${auth[@]}"}" || true)"
  if [[ -n "${slsa}" ]]; then
    source="$(jq -r '.source' <<<"${slsa}")"
    revision="$(jq -r '.revision' <<<"${slsa}")"
    slsa_built_at="$(jq -r '.built_at' <<<"${slsa}")"
  fi

  jq -n --arg source "${source}" --arg revision "${revision}" \
    --arg built_at "${built_at}" --arg slsa_built_at "${slsa_built_at}" \
    '{source: $source, revision: $revision, built_at: $built_at, slsa_built_at: $slsa_built_at}'
}

# BuildKit ties provenance to the image via vnd.docker.reference.digest
fetch_slsa_vcs() {
  local api_host="$1" path="$2" tag="$3" amd64="$4"
  shift 4
  local -a auth=("$@")
  [[ -n "${amd64}" ]] || return 1

  local index attestation layer predicate
  local index_accept="application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json"
  index="$(fetch "${auth[@]+"${auth[@]}"}" -H "Accept: ${index_accept}" \
    "https://${api_host}/v2/${path}/manifests/${tag}" 2>/dev/null)" || return 1
  attestation="$(jq -r --arg d "${amd64}" '.manifests[]? | select(.annotations["vnd.docker.reference.digest"] == $d) | .digest' <<<"${index}" | head -1)"
  [[ -n "${attestation}" ]] || return 1

  layer="$(fetch "${auth[@]+"${auth[@]}"}" -H "Accept: application/vnd.oci.image.manifest.v1+json" \
    "https://${api_host}/v2/${path}/manifests/${attestation}" 2>/dev/null |
    jq -r '.layers[]? | select(.annotations["in-toto.io/predicate-type"] == "https://slsa.dev/provenance/v1") | .digest' | head -1)"
  [[ -n "${layer}" ]] || return 1

  predicate="$(fetch "${auth[@]+"${auth[@]}"}" "https://${api_host}/v2/${path}/blobs/${layer}" 2>/dev/null)" || return 1
  jq -e '{
    source: (.predicate.buildDefinition.externalParameters.request.root.request.args["vcs:source"] // ""),
    revision: (.predicate.buildDefinition.externalParameters.request.root.request.args["vcs:revision"] // ""),
    built_at: (.predicate.runDetails.metadata.startedOn // "")
  } | select(.source != "" and .revision != "")' <<<"${predicate}" 2>/dev/null
}

fetch_upstream_facts() {
  local source="$1" revision="$2"
  local slug="${source#https://github.com/}"
  slug="${slug%.git}"

  if [[ -z "${source}" ]] || [[ -z "${revision}" ]] || [[ "${slug}" = "${source}" ]]; then
    jq -n '{repo_exists: false, commit_exists: false, branches: [], committed_at: ""}'
    return
  fi

  if ! gh api "repos/${slug}" --jq '.full_name' >/dev/null 2>&1; then
    jq -n '{repo_exists: false, commit_exists: false, branches: [], committed_at: ""}'
    return
  fi

  local committed_at
  if ! committed_at="$(gh api "repos/${slug}/commits/${revision}" --jq '.commit.committer.date' 2>/dev/null)"; then
    jq -n '{repo_exists: true, commit_exists: false, branches: [], committed_at: ""}'
    return
  fi

  # A commit can exist while reachable only from a fork or a deleted ref
  local branches
  branches="$(reachable_branches "${slug}" "${revision}")"

  jq -n --argjson branches "${branches}" --arg committed_at "${committed_at}" \
    '{repo_exists: true, commit_exists: true, branches: $branches, committed_at: $committed_at}'
}

reachable_branches() {
  local slug="$1" revision="$2"
  local -a found=()
  local heads branch status

  heads="$(gh api "repos/${slug}/commits/${revision}/branches-where-head" --jq '.[].name' 2>/dev/null || true)"
  while IFS= read -r branch; do
    [[ -n "${branch}" ]] && found+=("${branch}")
  done <<<"${heads}"

  if [[ "${#found[@]}" -eq 0 ]]; then
    while IFS= read -r branch; do
      [[ -n "${branch}" ]] || continue
      status="$(gh api "repos/${slug}/compare/${branch}...${revision}" --jq '.status' 2>/dev/null || true)"
      case "${status}" in
      identical | behind)
        found+=("${branch}")
        break
        ;;
      esac
    done < <(gh api "repos/${slug}/branches?per_page=100" --jq '.[].name' 2>/dev/null || true)
  fi

  printf '%s\n' "${found[@]+"${found[@]}"}" | jq -R . | jq -sc 'map(select(. != ""))'
}

allowlisted() {
  local repo="${1%%@*}"
  repo="${repo%:*}"
  [[ -f "${ALLOWLIST}" ]] || return 1
  grep -qxF "${repo}" <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "${ALLOWLIST}" | grep -v '^$')
}

epoch() {
  [[ -n "$1" ]] || return 1
  date -u -d "$1" +%s 2>/dev/null
}

verify() {
  local ref="$1" facts

  if [[ -n "${PROVENANCE_OFFLINE_FIXTURE:-}" ]]; then
    facts="$(cat "${PROVENANCE_OFFLINE_FIXTURE}")"
  else
    local registry upstream
    # die() inside the command substitution exits only the subshell
    if ! registry="$(fetch_registry_facts "${ref}")" || [[ -z "${registry}" ]]; then
      echo "FAILED ${ref} — registry lookup failed"
      return 1
    fi
    upstream="$(fetch_upstream_facts "$(jq -r '.source' <<<"${registry}")" "$(jq -r '.revision' <<<"${registry}")")"
    facts="$(jq -s '.[0] * .[1]' <<<"${registry}${upstream}")"
  fi

  local source revision repo_exists commit_exists branch_count built_at committed_at
  source="$(jq -r '.source' <<<"${facts}")"
  revision="$(jq -r '.revision' <<<"${facts}")"
  repo_exists="$(jq -r '.repo_exists' <<<"${facts}")"
  commit_exists="$(jq -r '.commit_exists' <<<"${facts}")"
  branch_count="$(jq -r '.branches | length' <<<"${facts}")"
  # config.created is often a reproducible-build epoch, not the real build time
  built_at="$(jq -r 'if (.slsa_built_at // "") != "" then .slsa_built_at else .built_at end' <<<"${facts}")"
  committed_at="$(jq -r '.committed_at' <<<"${facts}")"

  if [[ -z "${source}" ]] || [[ -z "${revision}" ]]; then
    if allowlisted "${ref}"; then
      echo "UNVERIFIABLE ${ref} — publisher exposes no provenance, allowlisted"
      return 0
    fi
    echo "FAILED ${ref} — no provenance labels and not on the allowlist"
    return 1
  fi

  if [[ "${repo_exists}" != "true" ]]; then
    echo "FAILED ${ref} — source repository ${source} does not exist"
    return 1
  fi

  if [[ "${commit_exists}" != "true" ]]; then
    echo "FAILED ${ref} — build commit ${revision} does not exist in ${source}"
    return 1
  fi

  if [[ "${branch_count}" -eq 0 ]]; then
    echo "FAILED ${ref} — build commit ${revision} is not reachable from any branch in ${source}"
    return 1
  fi

  local built_epoch committed_epoch
  if built_epoch="$(epoch "${built_at}")" && committed_epoch="$(epoch "${committed_at}")"; then
    if [[ "${built_epoch}" -lt $((committed_epoch - CLOCK_SKEW_SECONDS)) ]]; then
      echo "FAILED ${ref} — build time ${built_at} predates its source commit ${committed_at}"
      return 1
    fi
  fi

  echo "VERIFIED ${ref} — built from ${revision} on $(jq -r '.branches | join(", ")' <<<"${facts}") in ${source}"
}

list_refs() {
  awk '
    /^[[:space:]]*repository:[[:space:]]/ {
      match($0, /^[[:space:]]*/)
      repo_indent = RLENGTH
      repo = $2
      gsub(/["'\''"]/, "", repo)
      next
    }
    /^[[:space:]]*tag:[[:space:]]/ {
      match($0, /^[[:space:]]*/)
      if (repo != "" && RLENGTH == repo_indent) {
        tag = $2
        gsub(/["'\''"]/, "", tag)
        print repo ":" tag
        repo = ""
      }
      next
    }
    # a key at or above the repository indent ends its block
    /^[[:space:]]*[^[:space:]#-]/ {
      match($0, /^[[:space:]]*/)
      if (repo != "" && RLENGTH < repo_indent) repo = ""
    }
    /^[[:space:]]*-?[[:space:]]*image:[[:space:]]/ {
      for (i = 1; i <= NF; i++) {
        if ($i == "image:") {
          ref = $(i + 1)
          gsub(/["'\''"]/, "", ref)
          if (ref ~ /\//) print ref
        }
      }
    }
  ' "$@" | sort -u
}

main() {
  case "${1:-}" in
  --list-refs)
    shift
    list_refs "$@"
    ;;
  --verify)
    shift
    [[ $# -ge 1 ]] || die "usage: $0 --verify <image-ref>"
    require jq
    [[ -n "${PROVENANCE_OFFLINE_FIXTURE:-}" ]] || require curl gh
    local failed=0
    for ref in "$@"; do
      verify "${ref}" || failed=1
    done
    return "${failed}"
    ;;
  *)
    die "usage: $0 --list-refs <file>... | --verify <image-ref>..."
    ;;
  esac
}

main "$@"
