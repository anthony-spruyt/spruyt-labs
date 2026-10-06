#!/usr/bin/env bats
#
# values.yaml wires the middleware the way its integration tests boot it, at the deployed release. Ref #3398

REPO_ROOT="${BATS_TEST_DIRNAME}/.."
VALUES="${REPO_ROOT}/cluster/apps/litellm/litellm/app/values.yaml"
MIDDLEWARE_REPO="anthony-spruyt/litellm-middleware"

setup_file() {
  local tag version base
  tag="$(yq -e '.persistence.litellm-middleware.image.tag' "${VALUES}")"
  version="${tag%%@*}"
  base="https://raw.githubusercontent.com/${MIDDLEWARE_REPO}/v${version}"
  CONTRACT="$(mktemp -d)"
  curl -fsSL --retry 3 "${base}/tests/integration/conftest.py" -o "${CONTRACT}/conftest.py"
  curl -fsSL --retry 3 "${base}/Dockerfile" -o "${CONTRACT}/Dockerfile"
  export CONTRACT
}

teardown_file() {
  rm -rf "${CONTRACT}"
}

contract_const() {
  sed -nE "s/^${1} = \"([^\"]+)\"$/\1/p" "${CONTRACT}/conftest.py"
}

@test "the middleware callback is registered with LiteLLM" {
  local callback
  callback="$(contract_const CALLBACK)"
  [ -n "${callback}" ] || {
    echo "no CALLBACK constant in the middleware's conftest.py" >&2
    return 1
  }
  run yq -e '.configMaps.litellm-config.data."config.yaml"' "${VALUES}"
  [ "${status}" -eq 0 ]
  echo "${output}" | CALLBACK="${callback}" yq -e '.litellm_settings.callbacks | any_c(. == strenv(CALLBACK))' >/dev/null || {
    echo "litellm_settings.callbacks lacks ${callback}" >&2
    return 1
  }
}

@test "the middleware image volume mounts where the middleware expects" {
  local mount mounts
  mount="$(contract_const MOUNT_PATH)"
  [ -n "${mount}" ] || {
    echo "no MOUNT_PATH constant in the middleware's conftest.py" >&2
    return 1
  }
  mounts="$(yq -e '.persistence.litellm-middleware.advancedMounts.litellm.litellm[].path' "${VALUES}")"
  [ "${mounts}" = "${mount}" ] || {
    echo "litellm-middleware mounts at '${mounts}', the middleware expects ${mount}" >&2
    return 1
  }
}

@test "the mount path is on the LiteLLM container's PYTHONPATH" {
  local mount pythonpath
  mount="$(contract_const MOUNT_PATH)"
  pythonpath="$(yq -e '.controllers.litellm.containers.litellm.env.PYTHONPATH' "${VALUES}")"
  [[ ":${pythonpath}:" == *":${mount}:"* ]] || {
    echo "PYTHONPATH '${pythonpath}' does not include ${mount}" >&2
    return 1
  }
}

@test "the callback's top-level package is what the image ships" {
  local package shipped
  package="$(contract_const CALLBACK)"
  package="${package%%.*}"
  shipped="$(sed -nE 's|^COPY [^ ]+ /([^/ ]+)/?$|\1|p' "${CONTRACT}/Dockerfile")"
  [ "${shipped}" = "${package}" ] || {
    echo "the image ships '${shipped}' at its root, the callback imports ${package}" >&2
    return 1
  }
}
