#!/usr/bin/env bats
#
# CRD sources own the tag their controller image also carries. Ref #2698

REPO_ROOT="${BATS_TEST_DIRNAME}/.."

GIT_SOURCES="${REPO_ROOT}/cluster/flux/meta/repositories/git"
CSI_ADDONS_CONTROLLER="${REPO_ROOT}/cluster/apps/csi-addons-system/csi-addons-controller-manager/app/setup-controller.yaml"
SNAPSHOT_CONTROLLER="${REPO_ROOT}/cluster/apps/kube-system/snapshot-controller/app/setup-snapshot-controller.yaml"

gitrepo_tag() {
  grep -A2 '^  ref:' "$1" | grep -oE 'tag:[[:space:]]+\S+' | awk '{print $2}'
}

image_tag() {
  grep -oE "image:[[:space:]]+${2}:[^@[:space:]]+" "$1" | sed -E 's/.*://'
}

assert_paired() {
  local name="$1" source_tag="$2" image_tag="$3"

  [ -n "${source_tag}" ] || {
    echo "could not parse a tag from the ${name} GitRepository" >&2
    return 1
  }
  [ -n "${image_tag}" ] || {
    echo "could not parse a tag from the ${name} controller image" >&2
    return 1
  }
  [ "${source_tag}" = "${image_tag}" ] || {
    echo "${name}: CRD source is ${source_tag} but the controller image is ${image_tag}" >&2
    return 1
  }
}

@test "csi-addons CRD source matches the controller image" {
  assert_paired "csi-addons" \
    "$(gitrepo_tag "${GIT_SOURCES}/csi-addons-gitrepo.yaml")" \
    "$(image_tag "${CSI_ADDONS_CONTROLLER}" 'quay.io/csiaddons/k8s-controller')"
}

@test "external-snapshotter CRD source matches the snapshot-controller image" {
  assert_paired "external-snapshotter" \
    "$(gitrepo_tag "${GIT_SOURCES}/external-snapshotter-gitrepo.yaml")" \
    "$(image_tag "${SNAPSHOT_CONTROLLER}" 'registry.k8s.io/sig-storage/snapshot-controller')"
}

# gateway-api and vpa share no version string with their consumers and are
# gated on dashboard approval in .github/renovate-overrides.json5 instead.
@test "every GitRepository CRD source is accounted for" {
  local expected="csi-addons-gitrepo external-snapshotter-gitrepo gateway-api-gitrepo vpa-gitrepo"
  local found
  found="$(find "${GIT_SOURCES}" -name '*-gitrepo.yaml' -exec basename {} .yaml \; | sort | tr '\n' ' ')"

  [ "${found% }" = "${expected}" ] || {
    echo "GitRepository sources changed: expected '${expected}', found '${found% }'" >&2
    echo "a new CRD source needs a pairing assertion or a dashboard gate" >&2
    return 1
  }
}
