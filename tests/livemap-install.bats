#!/usr/bin/env bats
#
# The live map install hook keeps the last good install, never prints the key and always exits 0. Ref #3892

REPO_ROOT="${BATS_TEST_DIRNAME}/.."
APP="${REPO_ROOT}/cluster/apps/enshrouded/enshrouded/app"
SCRIPT="${APP}/livemap-install.sh"
VALUES="${APP}/values.yaml"
POLICIES="${APP}/network-policies.yaml"
INGRESS_ROUTES="${REPO_ROOT}/cluster/apps/traefik/traefik/ingress/enshrouded/ingress-routes.yaml"
WRONG_SHA="0000000000000000000000000000000000000000000000000000000000000000"

make_zip() {
  local src="${WORK}/src-$1"
  mkdir -p "${src}/livemap"
  printf 'dll-%s' "$1" >"${src}/iphlpapi.dll"
  printf 'index-%s' "$1" >"${src}/livemap/index.html"
  printf 'maps-%s' "$1" >"${src}/livemap/maps.json"
  python3 -I -m zipfile -c "${WORK}/release-$1.zip" "${src}/iphlpapi.dll" "${src}/livemap"
}

sha_of() {
  sha256sum "${WORK}/release-$1.zip" | cut -d' ' -f1
}

ini_get() {
  python3 -I -c 'import configparser, sys
c = configparser.ConfigParser()
c.read(sys.argv[1])
print(c["livemap"][sys.argv[2]])' "${LIVEMAP_ROOT}/livemap.ini" "$1"
}

manifest_map_ports() {
  python3 -I - "${VALUES}" "${POLICIES}" "${INGRESS_ROUTES}" <<'PY'
import sys
import yaml

with open(sys.argv[1]) as f:
    values = yaml.safe_load(f)
with open(sys.argv[2]) as f:
    policies = list(yaml.safe_load_all(f))
with open(sys.argv[3]) as f:
    routes = list(yaml.safe_load_all(f))

container = next(
    p["containerPort"]
    for p in values["controllers"]["enshrouded"]["containers"]["app"]["ports"]
    if p["name"] == "map"
)
service = values["service"]["map"]["ports"]["map"]["port"]
policy = next(d for d in policies if d["metadata"]["name"] == "allow-traefik-livemap-ingress")
allowed = [
    p["port"]
    for rule in policy["spec"]["ingress"]
    for to in rule["toPorts"]
    for p in to["ports"]
    if p["protocol"] == "TCP"
]
routed = [
    svc["port"]
    for d in routes
    for route in d["spec"]["routes"]
    for svc in route["services"]
    if svc["name"] == "enshrouded-map"
]
for port in [container, service, *allowed, *routed]:
    print(port)
PY
}

curl_calls() {
  wc -l <"${CALLS}"
}

assert_invalid_key_falls_back() {
  printf '[livemap]\nKey=kept-key-1234\n' >"${LIVEMAP_ROOT}/livemap.ini"
  run env LIVEMAP_KEY="$1" bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(ini_get key)" = "kept-key-1234" ]
  rm "${LIVEMAP_ROOT}/livemap.ini"
  run env LIVEMAP_KEY="$1" bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [[ "$(ini_get key)" =~ ^[abcdefghjkmnpqrstuvwxyz23456789]{16}$ ]]
}

setup() {
  WORK="$(mktemp -d)"
  BIN="${WORK}/bin"
  mkdir -p "${BIN}"
  export CALLS="${WORK}/curl-calls"
  : >"${CALLS}"
  cat >"${BIN}/curl" <<'EOF'
#!/bin/bash
echo "$*" >>"${CALLS}"
[ -z "${FAKE_CURL_EXIT:-}" ] || exit "${FAKE_CURL_EXIT}"
while [ $# -gt 0 ]; do
  [ "$1" = "-o" ] && out="$2"
  shift
done
cp "${FAKE_ZIP}" "${out}"
EOF
  chmod +x "${BIN}/curl"
  export PATH="${BIN}:${PATH}"

  make_zip v1
  export FAKE_ZIP="${WORK}/release-v1.zip"
  export LIVEMAP_ROOT="${WORK}/root"
  mkdir -p "${LIVEMAP_ROOT}"
  export LIVEMAP_VERSION="v1.7.0"
  LIVEMAP_SHA256="$(sha_of v1)"
  export LIVEMAP_SHA256
  export LIVEMAP_PUBLIC_URL="https://enshrouded-map.example.test"
  unset LIVEMAP_KEY
}

teardown() {
  rm -rf "${WORK}"
}

@test "installs the DLL and the web files from the release and records its hash" {
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(<"${LIVEMAP_ROOT}/iphlpapi.dll")" = "dll-v1" ]
  [ "$(<"${LIVEMAP_ROOT}/livemap/index.html")" = "index-v1" ]
  [ "$(<"${LIVEMAP_ROOT}/livemap/maps.json")" = "maps-v1" ]
  [ "$(<"${LIVEMAP_ROOT}/livemap/.installed")" = "${LIVEMAP_SHA256}" ]
  [ "$(curl_calls)" -eq 1 ]
}

@test "downloads the release asset named after the version without the v" {
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  grep -q 'github.com/oggii/enshrouded-livemap/releases/download/v1.7.0/EnshroudedLiveMap-1.7.0.zip' "${CALLS}"
}

@test "the worst-case download time leaves 30 s of the 300 s hook timeout" {
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  local max retry
  max="$(grep -o -e '--max-time [0-9]*' "${CALLS}" | cut -d' ' -f2)"
  retry="$(grep -o -e '--retry [0-9]*' "${CALLS}" | cut -d' ' -f2)"
  [ -n "${max}" ]
  [ -n "${retry}" ]
  [ $(((retry + 1) * max + (1 << retry) - 1)) -le 270 ]
}

@test "writes livemap.ini with the livemap section, the public URL, the port the pod serves the map on and a random 16 character key" {
  local first second port declared
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(head -n1 "${LIVEMAP_ROOT}/livemap.ini")" = "[livemap]" ]
  first="$(ini_get key)"
  [ "$(ini_get publicurl)" = "${LIVEMAP_PUBLIC_URL}" ]
  port="$(ini_get port)"
  run manifest_map_ports
  echo "${output}"
  [ "${status}" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  for declared in "${lines[@]}"; do
    [ "${declared}" = "${port}" ]
  done
  rm "${LIVEMAP_ROOT}/livemap.ini"
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  second="$(ini_get key)"
  [[ "${first}" =~ ^[abcdefghjkmnpqrstuvwxyz23456789]{16}$ ]]
  [[ "${second}" =~ ^[abcdefghjkmnpqrstuvwxyz23456789]{16}$ ]]
  [ "${first}" != "${second}" ]
}

@test "a second run keeps the key and does not download again" {
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  local first
  first="$(ini_get key)"
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(ini_get key)" = "${first}" ]
  [ "$(curl_calls)" -eq 1 ]
}

@test "keeps a key that is already in livemap.ini, whatever its line endings and case" {
  printf '[Other]\r\nKey=wrong\r\n[LiveMap]\r\nPort=auto\r\nKEY = my-custom_Key9 \r\n' >"${LIVEMAP_ROOT}/livemap.ini"
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(ini_get key)" = "my-custom_Key9" ]
}

@test "a missing DLL forces a reinstall" {
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  printf 'stale' >"${LIVEMAP_ROOT}/livemap/maps.json"
  rm "${LIVEMAP_ROOT}/iphlpapi.dll"
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(<"${LIVEMAP_ROOT}/iphlpapi.dll")" = "dll-v1" ]
  [ "$(<"${LIVEMAP_ROOT}/livemap/maps.json")" = "maps-v1" ]
  [ "$(curl_calls)" -eq 2 ]
}

@test "a missing index.html forces a reinstall" {
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  rm "${LIVEMAP_ROOT}/livemap/index.html"
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(<"${LIVEMAP_ROOT}/livemap/index.html")" = "index-v1" ]
  [ "$(curl_calls)" -eq 2 ]
}

@test "a reinstall swaps the DLL in by rename and leaves a copy the server has open untouched" {
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  make_zip v2
  exec {held}<"${LIVEMAP_ROOT}/iphlpapi.dll"
  run env FAKE_ZIP="${WORK}/release-v2.zip" LIVEMAP_VERSION=v2.0.0 LIVEMAP_SHA256="$(sha_of v2)" bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(<"${LIVEMAP_ROOT}/iphlpapi.dll")" = "dll-v2" ]
  [ "$(cat <&"${held}")" = "dll-v1" ]
  exec {held}<&-
  [ ! -e "${LIVEMAP_ROOT}/iphlpapi.dll.new" ]
}

@test "history files survive a reinstall" {
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  printf '{"deaths":1}' >"${LIVEMAP_ROOT}/livemap/deaths.json"
  printf '{"finds":1}' >"${LIVEMAP_ROOT}/livemap/finds.json"
  rm "${LIVEMAP_ROOT}/iphlpapi.dll"
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(curl_calls)" -eq 2 ]
  [ "$(<"${LIVEMAP_ROOT}/livemap/deaths.json")" = '{"deaths":1}' ]
  [ "$(<"${LIVEMAP_ROOT}/livemap/finds.json")" = '{"finds":1}' ]
}

@test "a wrong hash keeps the installed files and exits 0" {
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  local first
  first="$(ini_get key)"
  make_zip v2
  export FAKE_ZIP="${WORK}/release-v2.zip"
  run env LIVEMAP_VERSION=v2.0.0 LIVEMAP_SHA256="${WRONG_SHA}" bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(curl_calls)" -eq 2 ]
  [ "$(<"${LIVEMAP_ROOT}/iphlpapi.dll")" = "dll-v1" ]
  [ "$(<"${LIVEMAP_ROOT}/livemap/index.html")" = "index-v1" ]
  [ "$(<"${LIVEMAP_ROOT}/livemap/.installed")" = "$(sha_of v1)" ]
  [ "$(ini_get key)" = "${first}" ]
}

@test "a failed download keeps the installed files and exits 0" {
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  local first
  first="$(ini_get key)"
  make_zip v2
  run env FAKE_CURL_EXIT=22 LIVEMAP_VERSION=v9.9.9 LIVEMAP_SHA256="$(sha_of v2)" bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"livemap-install: download of v9.9.9 failed (curl exit 22), keeping installed files"* ]]
  [ "$(curl_calls)" -eq 2 ]
  [ "$(<"${LIVEMAP_ROOT}/iphlpapi.dll")" = "dll-v1" ]
  [ "$(<"${LIVEMAP_ROOT}/livemap/index.html")" = "index-v1" ]
  [ "$(<"${LIVEMAP_ROOT}/livemap/.installed")" = "$(sha_of v1)" ]
  [ "$(ini_get key)" = "${first}" ]
}

@test "a failed first download still writes livemap.ini and exits 0" {
  run env FAKE_CURL_EXIT=22 bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ ! -e "${LIVEMAP_ROOT}/iphlpapi.dll" ]
  [ ! -e "${LIVEMAP_ROOT}/livemap/.installed" ]
  [ "$(head -n1 "${LIVEMAP_ROOT}/livemap.ini")" = "[livemap]" ]
  [ "$(ini_get key | wc -c)" -eq 17 ]
}

@test "no run prints the key" {
  local all key
  run bash "${SCRIPT}"
  all="${output}"
  key="$(ini_get key)"
  run bash "${SCRIPT}"
  all+="${output}"
  make_zip v2
  run env LIVEMAP_VERSION=v2.0.0 LIVEMAP_SHA256="${WRONG_SHA}" bash "${SCRIPT}"
  all+="${output}"
  run env FAKE_CURL_EXIT=22 LIVEMAP_VERSION=v9.9.9 LIVEMAP_SHA256="$(sha_of v2)" bash "${SCRIPT}"
  all+="${output}"
  [ -n "${key}" ]
  [ -n "${all}" ]
  [[ "${all}" != *"${key}"* ]]
}

@test "trims livemap.log to its last 1000 lines when it is over 10 MB" {
  local log="${LIVEMAP_ROOT}/livemap.log"
  awk 'BEGIN { for (i = 1; i <= 300000; i++) print "line " i " ........................................" }' >"${log}"
  [ "$(stat -c %s "${log}")" -gt 10485760 ]
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(wc -l <"${log}")" -eq 1000 ]
  [ "$(head -n1 "${log}")" = "line 299001 ........................................" ]
  [ "$(tail -n1 "${log}")" = "line 300000 ........................................" ]
}

@test "leaves a livemap.log under 10 MB alone, however many lines it has" {
  local log="${LIVEMAP_ROOT}/livemap.log"
  seq 1 5000 >"${log}"
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(wc -l <"${log}")" -eq 5000 ]
  [ "$(head -n1 "${log}")" = "1" ]
}

@test "writes the key from LIVEMAP_KEY" {
  run env LIVEMAP_KEY="Env-key_0123456789" bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(ini_get key)" = "Env-key_0123456789" ]
}

@test "a LIVEMAP_KEY replaces a different key already in livemap.ini" {
  printf '[livemap]\nKey=old-key-1234\nPort=auto\n' >"${LIVEMAP_ROOT}/livemap.ini"
  run env LIVEMAP_KEY="envkey4567" bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(ini_get key)" = "envkey4567" ]
  run manifest_map_ports
  echo "${output}"
  [ "${status}" -eq 0 ]
  [ "$(ini_get port)" = "${lines[0]}" ]
}

@test "a LIVEMAP_KEY of 3 and of 64 characters is accepted" {
  run env LIVEMAP_KEY="a-_" bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(ini_get key)" = "a-_" ]
  local long
  long="$(printf 'k%.0s' {1..64})"
  run env LIVEMAP_KEY="${long}" bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(ini_get key)" = "${long}" ]
}

@test "a LIVEMAP_KEY with a character outside letters, digits, - and _ falls back to the old behaviour" {
  assert_invalid_key_falls_back "bad key!"
  assert_invalid_key_falls_back "line
break"
  assert_invalid_key_falls_back "dot.dot"
  assert_invalid_key_falls_back $'abcd\n'
}

@test "a LIVEMAP_KEY with an accented letter falls back, even in a UTF-8 locale where A-Za-z can match it" {
  locale -a | grep -qix 'en_US\.utf-\?8' || skip "the en_US.UTF-8 locale is not installed"
  export LC_ALL=en_US.UTF-8
  assert_invalid_key_falls_back $'caf\xc3\xa9key'
}

@test "a LIVEMAP_KEY shorter than 3 characters falls back to the old behaviour" {
  assert_invalid_key_falls_back "ab"
}

@test "a LIVEMAP_KEY longer than 64 characters falls back to the old behaviour" {
  assert_invalid_key_falls_back "$(printf 'k%.0s' {1..65})"
}

@test "a reserved LIVEMAP_KEY falls back to the old behaviour, whatever its case" {
  local word
  for word in state events finds icons index livemap State EVENTS Finds iCoNs INDEX LiveMap; do
    assert_invalid_key_falls_back "${word}"
  done
}

@test "an empty LIVEMAP_KEY falls back to the old behaviour" {
  assert_invalid_key_falls_back ""
}

@test "an ignored LIVEMAP_KEY is logged without its value" {
  local bad
  for bad in "bad key!" "q9" "ICONS" "$(printf 'k%.0s' {1..65})"; do
    run env LIVEMAP_KEY="${bad}" bash "${SCRIPT}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"livemap-install: LIVEMAP_KEY is not a valid map key"* ]]
    [[ "${output}" != *"${bad}"* ]]
  done
}

@test "an unset, empty or valid LIVEMAP_KEY is not logged as invalid" {
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"LIVEMAP_KEY"* ]]
  run env LIVEMAP_KEY="" bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"LIVEMAP_KEY"* ]]
  run env LIVEMAP_KEY="Env-key_0123456789" bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"LIVEMAP_KEY"* ]]
}

@test "no run prints a LIVEMAP_KEY" {
  local all key="Env-key_0123456789"
  run env LIVEMAP_KEY="${key}" bash "${SCRIPT}"
  all="${output}"
  [ "$(ini_get key)" = "${key}" ]
  run env LIVEMAP_KEY="${key}" bash "${SCRIPT}"
  all+="${output}"
  make_zip v2
  run env LIVEMAP_KEY="${key}" LIVEMAP_VERSION=v2.0.0 LIVEMAP_SHA256="${WRONG_SHA}" bash "${SCRIPT}"
  all+="${output}"
  run env LIVEMAP_KEY="${key}" FAKE_CURL_EXIT=22 LIVEMAP_VERSION=v9.9.9 LIVEMAP_SHA256="$(sha_of v2)" bash "${SCRIPT}"
  all+="${output}"
  run env LIVEMAP_KEY="bad key!" bash "${SCRIPT}"
  all+="${output}"
  [ -n "${all}" ]
  [[ "${all}" != *"${key}"* ]]
  [[ "${all}" != *"bad key!"* ]]
}

@test "the script has no braced variable for Flux to substitute in the ConfigMap" {
  run grep -c -F '${' "${SCRIPT}"
  [ "${output}" = "0" ]
}
