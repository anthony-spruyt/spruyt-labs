#!/usr/bin/env bats
#
# The live map install hook keeps the last good install, never prints the key and always exits 0. Ref #3892

REPO_ROOT="${BATS_TEST_DIRNAME}/.."
SCRIPT="${REPO_ROOT}/cluster/apps/enshrouded/enshrouded/app/livemap-install.sh"
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

curl_calls() {
  wc -l <"${CALLS}"
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

@test "writes livemap.ini with the livemap section, every setting and a 16 character key" {
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(head -n1 "${LIVEMAP_ROOT}/livemap.ini")" = "[livemap]" ]
  python3 -I - "${LIVEMAP_ROOT}/livemap.ini" <<'PY'
import configparser, re, sys

c = configparser.ConfigParser()
c.read(sys.argv[1])
assert c.sections() == ["livemap"], c.sections()
s = c["livemap"]
want = {
    "enabled": "1",
    "port": "15637",
    "bind": "0.0.0.0",
    "publicurl": "https://enshrouded-map.example.test",
    "detectpublicaddress": "0",
    "announceinchat": "1",
    "updatems": "250",
    "log": "1",
    "logdiagnostics": "0",
}
for k, v in want.items():
    assert s[k] == v, k
assert set(s.keys()) == set(want) | {"key"}, sorted(s.keys())
assert re.fullmatch(r"[abcdefghjkmnpqrstuvwxyz23456789]{16}", s["key"]), "key is not 16 characters from the alphabet"
PY
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
