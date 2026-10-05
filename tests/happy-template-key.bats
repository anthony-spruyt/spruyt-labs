#!/usr/bin/env bats
#
# Rotating a Coder template's Happy key pairs against the self-hosted server and writes only the encrypted secret. Ref #3314

REPO_ROOT="${BATS_TEST_DIRNAME}/.."

setup() {
  TREE="$(mktemp -d)"
  mkdir -p "${TREE}/.taskfiles/happy/scripts" "${TREE}/cluster/apps/coder-workspaces/coder-workspaces/app"
  cp "${REPO_ROOT}/.taskfiles/happy/scripts/rotate-template-key.sh" "${TREE}/.taskfiles/happy/scripts/"
  SCRIPT="${TREE}/.taskfiles/happy/scripts/rotate-template-key.sh"
  KEYS="${TREE}/cluster/apps/coder-workspaces/coder-workspaces/app"

  BIN="$(mktemp -d)"
  cat >"${BIN}/npx" <<'EOF'
#!/bin/bash
echo "npx $* server=${HAPPY_SERVER_URL} webapp=${HAPPY_WEBAPP_URL}" >>"${CALLS}"
[ -n "${NPX_FAIL:-}" ] && exit 1
printf 'paired-key' >"${HAPPY_HOME_DIR}/access.key"
EOF
  cat >"${BIN}/kubectl" <<'EOF'
#!/bin/bash
case "$*" in
  *"get certificate"*) echo "happy.example.test" ;;
  *"create secret"*) echo "kubectl-secret $*" ;;
esac
EOF
  cat >"${BIN}/sops" <<'EOF'
#!/bin/bash
echo "sops $*" >>"${CALLS}"
sed 's/^/ENC:/'
EOF
  chmod +x "${BIN}"/*
  export CALLS="${BIN}/calls"
  export PATH="${BIN}:/usr/bin:/bin"
}

teardown() {
  rm -rf "${TREE}" "${BIN}"
}

@test "rejects a template that has no Happy key" {
  run bash "${SCRIPT}" nope
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"spruyt-labs"* ]]
  [ ! -e "${CALLS}" ]
}

@test "pairs against the server from the happy certificate" {
  run bash "${SCRIPT}" xfg
  [ "${status}" -eq 0 ] || {
    echo "${output}" >&2
    return 1
  }
  grep -q "happy auth login server=https://happy.example.test webapp=https://happy.example.test" "${CALLS}"
}

@test "writes the encrypted secret for that template" {
  run bash "${SCRIPT}" xfg
  [ "${status}" -eq 0 ] || {
    echo "${output}" >&2
    return 1
  }
  grep -q "^ENC:kubectl-secret create secret generic coder-happy-xfg -n coder-workspaces --from-file=access.key=" "${KEYS}/coder-happy-xfg.sops.yaml"
  grep -q -- "--filename-override ${KEYS}/coder-happy-xfg.sops.yaml" "${CALLS}"
}

@test "leaves the existing secret alone when pairing fails" {
  echo "old" >"${KEYS}/coder-happy-xfg.sops.yaml"
  NPX_FAIL=1 run bash "${SCRIPT}" xfg
  [ "${status}" -ne 0 ]
  [ "$(cat "${KEYS}/coder-happy-xfg.sops.yaml")" = "old" ]
}
