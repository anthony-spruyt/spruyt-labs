#!/usr/bin/env bats
#
# The live map cron swaps in the pinned release only while nobody plays, watches the server for 10 minutes
# and turns the map off for good when the server crashes on it. Every external command is a stub and the clock is fake. Ref #4105

# shellcheck disable=SC2030,SC2031
REPO_ROOT="${BATS_TEST_DIRNAME}/.."
APP="${REPO_ROOT}/cluster/apps/enshrouded/enshrouded/app"
SCRIPT="${APP}/livemap-install.sh"
VALUES="${APP}/values.yaml"
KUSTOMIZATION="${APP}/kustomization.yaml"
PIN_FILE="${APP}/livemap-pin.yaml"
VMRULES="${REPO_ROOT}/cluster/apps/observability/victoria-metrics-k8s-stack/app/vmrules"
CI_REPO="${REPO_ROOT}/.github/workflows/ci-repo.yaml"
V1=v1.0.0
V2=v2.0.0
BUILD=26404334
START=1800000000
STATUS_RE='^livemap-status\|state=(active|inactive|disabled|off) version=[^ ]+ build=[0-9a-z]+$'

make_stubs() {
  cat >"${BIN}/curl" <<'EOF'
#!/bin/bash
here="$(cd "$(dirname "$0")/.." && pwd)"
echo "$*" >>"${here}/curl-calls"
echo "curl" >>"${here}/events"
if [ -f "${here}/during-download" ]; then
  while IFS='|' read -r prog st pid; do
    echo "$(<"${here}/clock")|${st}|${pid}" >>"${here}/sv/${prog}"
  done <"${here}/during-download"
fi
[ ! -f "${here}/curl-exit" ] || exit "$(<"${here}/curl-exit")"
while [ $# -gt 0 ]; do
  [ "$1" = "-o" ] && out="$2"
  url="$1"
  shift
done
tag="$(sed -E 's#.*/download/([^/]+)/.*#\1#' <<<"${url}")"
[ -f "${here}/served/${tag}.zip" ] || exit 22
cp "${here}/served/${tag}.zip" "${out}"
EOF
  cat >"${BIN}/date" <<'EOF'
#!/bin/bash
here="$(cd "$(dirname "$0")/.." && pwd)"
case "$1" in
+%s) cat "${here}/clock" ;;
+%Y) exec /usr/bin/date -d "@$(<"${here}/clock")" +%Y ;;
*) exec /usr/bin/date "$@" ;;
esac
EOF
  cat >"${BIN}/sleep" <<'EOF'
#!/bin/bash
here="$(cd "$(dirname "$0")/.." && pwd)"
now=$(($(<"${here}/clock") + ${1%.*}))
echo "${now}" >"${here}/clock"
if [ -f "${here}/log-at" ]; then
  : >"${here}/log-at.rest"
  while read -r at kind; do
    if [ "${at}" -le "${now}" ]; then
      echo "2026-11-05 10:00:00,000 INFO ${kind}: enshrouded-server (exit status 1)" >>"${here}/supervisord.log"
    else
      echo "${at} ${kind}" >>"${here}/log-at.rest"
    fi
  done <"${here}/log-at"
  mv "${here}/log-at.rest" "${here}/log-at"
fi
EOF
  cat >"${BIN}/logger" <<'EOF'
#!/bin/bash
here="$(cd "$(dirname "$0")/.." && pwd)"
tag=""
while [ $# -gt 0 ]; do
  case "$1" in
  -t) tag="$2"; shift 2 ;;
  --) shift; break ;;
  *) break ;;
  esac
done
echo "${tag}|$*" >>"${here}/logger-calls"
EOF
  cat >"${BIN}/timeout" <<'EOF'
#!/bin/bash
here="$(cd "$(dirname "$0")/.." && pwd)"
echo "$*" >>"${here}/timeout-calls"
exec /usr/bin/timeout "$@"
EOF
  cat >"${BIN}/crontab" <<'EOF'
#!/bin/bash
f="$(dirname "$0")/../crontab"
[ ! -f "$(dirname "$0")/../crontab-broken" ] || exit 1
case "$1" in
-l) [ -f "${f}" ] && cat "${f}" ;;
-) cat >"${f}"; echo w >>"$(dirname "$0")/../crontab-writes" ;;
esac
EOF
  cat >"${BIN}/supervisorctl" <<'EOF'
#!/bin/bash
here="$(cd "$(dirname "$0")/.." && pwd)"
now="$(<"${here}/clock")"
echo "${now} $*" >>"${here}/supervisorctl-calls"
if [ -f "${here}/sv-down" ]; then
  echo "unix:///dev/shm/supervisor.sock no such file" >&2
  exit 2
fi
state_of() {
  awk -F'|' -v now="${now}" '$1 <= now { s = $2; p = $3; t = $1; b = $4 } END { print s, (p == "" ? "-" : p), t, (b == "" ? t : b) }' "${here}/sv/$1" 2>/dev/null
}
uptime_of() {
  local u=$((now - $1)) d
  d=$((u / 86400))
  u=$((u % 86400))
  [ "${d}" -eq 0 ] || printf '%d day%s, ' "${d}" "$([ "${d}" -eq 1 ] || echo s)"
  printf '%d:%02d:%02d' $((u / 3600)) $((u % 3600 / 60)) $((u % 60))
}
case "$1" in
status)
  rc=0
  for prog in "${@:2}"; do
    read -r st pid at started <<<"$(state_of "${prog}")"
    if [ -z "${st}" ]; then
      echo "${prog}: ERROR (no such process)"
      rc=2
    elif [ "${st}" = RUNNING ]; then
      printf '%-32s %-9s pid %s, uptime %s\n' "${prog}" "${st}" "${pid}" "$(uptime_of "${started}")"
    else
      printf '%-32s %-9s %s\n' "${prog}" "${st}" "$(TZ=Australia/Melbourne /usr/bin/date -d "@${at}" '+%b %d %I:%M %p')"
      [ "${rc}" -ne 0 ] || rc=3
    fi
  done
  exit "${rc}"
  ;;
restart)
  n=$(($(cat "${here}/restart-count" 2>/dev/null || echo 0) + 1))
  echo "${n}" >"${here}/restart-count"
  echo "restart" >>"${here}/events"
  echo "${now}|STOPPED|" >>"${here}/sv/$2"
  echo "2026-11-05 10:00:00,000 INFO stopped: $2 (terminated by SIGTERM)" >>"${here}/supervisord.log"
  [ ! -f "${here}/build-after-restart-${n}" ] || cp "${here}/build-after-restart-${n}" "${here}/current_version"
  done_at=${now}
  if [ ! -f "${here}/restart-exit-${n}" ]; then
    done_at=$((now + $(cat "${here}/restart-secs" 2>/dev/null || echo 70)))
    echo "${done_at}" >"${here}/clock"
    echo "${done_at}|RUNNING|$((900 + n))" >>"${here}/sv/$2"
  fi
  if [ -f "${here}/after-restart-${n}" ]; then
    while IFS='|' read -r off prog st pid; do
      echo "$((done_at + off))|${st}|${pid}" >>"${here}/sv/${prog}"
    done <"${here}/after-restart-${n}"
  fi
  if [ -f "${here}/restart-exit-${n}" ]; then
    exit "$(<"${here}/restart-exit-${n}")"
  fi
  echo "$2: stopped"
  echo "$2: started"
  ;;
*)
  exit 2
  ;;
esac
EOF
  cat >"${WORK}/common" <<'EOF'
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
checkServerEmpty() {
  local n rc
  echo "empty" >>"${here}/events"
  echo "$* $(<"${here}/clock") $(cat "${here}/root/iphlpapi.dll" 2>/dev/null)" >>"${here}/empty-calls"
  n=$(($(cat "${here}/empty-count" 2>/dev/null || echo 0) + 1))
  echo "${n}" >"${here}/empty-count"
  rc="$(sed -n "${n}p" "${here}/empty-seq" 2>/dev/null)"
  [ -n "${rc}" ] || rc="$(tail -n 1 "${here}/empty-seq" 2>/dev/null)"
  return "${rc:-0}"
}
EOF
  chmod +x "${BIN}"/*
}

sha_of() {
  sha256sum "${WORK}/served/$1.zip" | cut -d' ' -f1
}

make_release() {
  local src="${WORK}/src-$1"
  mkdir -p "${src}/livemap"
  printf 'dll-%s' "$1" >"${src}/iphlpapi.dll"
  printf 'index-%s' "$1" >"${src}/livemap/index.html"
  printf 'maps-%s' "$1" >"${src}/livemap/maps.json"
  if [ "${2:-}" = extra ]; then
    printf 'extra-%s' "$1" >"${src}/livemap/extra.js"
  fi
  python3 -I -m zipfile -c "${WORK}/served/$1.zip" "${src}/iphlpapi.dll" "${src}/livemap"
}

install_by_hand() {
  cp "${WORK}/src-$1/iphlpapi.dll" "${ROOT}/iphlpapi.dll"
  cp -R "${WORK}/src-$1/livemap/." "${ROOT}/livemap/"
  printf '%s\n%s\n' "$(sha_of "$1")" "$1" >"${ROOT}/livemap/.installed"
}

write_pin() {
  printf '# renovate: depName=anthony-spruyt/enshrouded-livemap datasource=github-release-attachments digest=sha256\nLIVEMAP_VERSION: "%s"\nLIVEMAP_SHA256: "%s"\n' \
    "$1" "${2:-$(sha_of "$1")}" >"${PINDIR}/livemap-pin.yaml"
}

assert_installed() {
  [ "$(<"${ROOT}/iphlpapi.dll")" = "dll-$1" ]
  [ "$(<"${ROOT}/livemap/index.html")" = "index-$1" ]
  [ "$(<"${ROOT}/livemap/maps.json")" = "maps-$1" ]
  [ "$(sed -n 1p "${ROOT}/livemap/.installed")" = "$(sha_of "$1")" ]
  [ "$(sed -n 2p "${ROOT}/livemap/.installed")" = "$1" ]
}

restarts() {
  cat "${WORK}/restart-count" 2>/dev/null || echo 0
}

downloads() {
  { cat "${WORK}/curl-calls" 2>/dev/null || true; } | wc -l
}

empty_checks() {
  cat "${WORK}/empty-count" 2>/dev/null || echo 0
}

events() {
  tr '\n' ' ' <"${WORK}/events"
}

# Lines are "offset|program|STATE|pid", the offset in seconds after the restart is done
after_restart() {
  local n="$1"
  shift
  printf '%s\n' "$@" >>"${WORK}/after-restart-${n}"
}

set_state() {
  echo "0|$2|${3:-}" >"${WORK}/sv/$1"
}

empty_seq() {
  printf '%s\n' "$@" >"${WORK}/empty-seq"
}

elapsed_since_restart_done() {
  echo $(($(<"${WORK}/clock") - START - ${1:-70}))
}

log_line() {
  printf '%s\r\n' "$@" >>"${ROOT}/livemap.log"
}

status_line() {
  grep '^livemap-status|' "${WORK}/logger-calls" | tail -n 1
}

advance() {
  echo $(($(<"${WORK}/clock") + $1)) >"${WORK}/clock"
}

crash_server() {
  advance 300
  echo "$(<"${WORK}/clock")|RUNNING|$1" >>"${WORK}/sv/enshrouded-server"
}

crash_line() {
  grep '^livemap-crash|' "${WORK}/logger-calls" | tail -n 1
}

crash_count() {
  { grep -c '^livemap-crash|' "${WORK}/logger-calls" 2>/dev/null || true; } | head -n 1
}

# The DLL stamps its lines in UTC; the offset is in seconds from START
utc_stamp() {
  /usr/bin/date -u -d "@$((START + $1))" '+%Y-%m-%d %H:%M:%S.000'
}

log_start() {
  log_line "$(utc_stamp "${1:--600}") livemap 1.0.0 starting: Enabled=1 Port=15637 real iphlpapi loaded"
}

log_fault() {
  log_line "$(utc_stamp "${1:--100}") [livemap] FAULT code=0xc0000005 at=livemap+0x1a2b site=movement"
}

# Has supervisord log a line for the server once the fake clock reaches START plus the offset, so a stop can happen during the watch
log_at() {
  echo "$((START + $1)) $2" >>"${WORK}/log-at"
}

# Appends a supervisord.log line for a program (the server by default); only the program and the word before it matter
sv_log() {
  local prog="${2:-enshrouded-server}"
  case "$1" in
  exited) echo "2026-11-05 10:00:00,000 INFO exited: ${prog} (exit status 1; not expected)" ;;
  stopped) echo "2026-11-05 10:00:00,000 INFO stopped: ${prog} (terminated by SIGTERM)" ;;
  esac >>"${WORK}/supervisord.log"
}

# Cron gives its job only the TZ the bootstrap wrote into the cron line; before any bootstrap the pod's zone stands in
cron_tz() {
  if [ -f "${WORK}/crontab" ]; then
    sed -n 's/^.* TZ=\([^ ]*\) .*livemap-install\.sh --cron.*$/\1/p' "${WORK}/crontab" | head -n 1
  else
    echo Australia/Melbourne
  fi
}

run_cron() {
  local tz tzenv=()
  tz="$(cron_tz)"
  if [ -n "${tz}" ]; then
    tzenv=(TZ="${tz}")
  fi
  run env -i PATH="${BIN}:/usr/bin:/bin" HOME="${WORK}" "${BASE_ENV[@]}" "${tzenv[@]}" "$@" bash "${SCRIPT}" --cron
}

run_boot() {
  run env -i PATH="${BIN}:/usr/bin:/bin" HOME="${WORK}" "${BASE_ENV[@]}" LIVEMAP_PUBLIC_URL=https://enshrouded-map.example.test "$@" bash "${SCRIPT}"
}

setup() {
  WORK="$(mktemp -d)"
  BIN="${WORK}/bin"
  ROOT="${WORK}/root"
  PINDIR="${WORK}/pin"
  STATE="${WORK}/state"
  BG_PIDS=()
  mkdir -p "${BIN}" "${ROOT}/livemap" "${PINDIR}" "${WORK}/sv" "${WORK}/served"
  echo "${START}" >"${WORK}/clock"
  make_stubs
  : >"${WORK}/supervisord.log"
  printf '%s\n' "${BUILD}" >"${WORK}/current_version"
  printf '0|RUNNING|100\n' >"${WORK}/sv/enshrouded-server"
  printf '0|EXITED|\n' >"${WORK}/sv/enshrouded-updater"
  make_release "${V1}"
  make_release "${V2}" extra
  install_by_hand "${V1}"
  write_pin "${V2}"
  BASE_ENV=(
    LIVEMAP_ROOT="${ROOT}"
    LIVEMAP_PIN_DIR="${PINDIR}"
    LIVEMAP_STATE_DIR="${STATE}"
    LIVEMAP_IMAGE_COMMON="${WORK}/common"
    LIVEMAP_UPDATER_PIDFILE="${WORK}/updater.pid"
    LIVEMAP_BUILD_FILE="${WORK}/current_version"
    LIVEMAP_CRON_LOCK="${WORK}/cron.lock"
    LIVEMAP_SERVER_RECORD="${WORK}/server-record"
    LIVEMAP_SUPERVISOR_LOG="${WORK}/supervisord.log"
    LIVEMAP_FATAL_MARKER="${WORK}/fatal-marker"
  )
}

teardown() {
  local pid
  for pid in "${BG_PIDS[@]}"; do
    kill -- "-${pid}" 2>/dev/null || kill "${pid}" 2>/dev/null || true
  done
  rm -rf "${WORK}"
}

@test "swaps in the pinned release while the server is empty and keeps what the server wrote" {
  printf '{"deaths":1}' >"${ROOT}/livemap/deaths.json"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ "$(restarts)" -eq 1 ]
  grep -q ' restart enshrouded-server$' "${WORK}/supervisorctl-calls"
  [ ! -s "${STATE}/bad-list" ]
  [ ! -e "${STATE}/last-good" ]
  [ "$(<"${ROOT}/livemap/deaths.json")" = '{"deaths":1}' ]
  [ ! -e "${ROOT}/iphlpapi.dll.new" ]
}

@test "does nothing when the installed release is the pinned one" {
  write_pin "${V1}"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V1}"
  [ "$(downloads)" -eq 0 ]
  [ "$(restarts)" -eq 0 ]
  [ "$(empty_checks)" -eq 0 ]
}

@test "checks for players before the download and again after it, and always asks for a real check" {
  run_cron
  [ "${status}" -eq 0 ]
  [ "$(empty_checks)" -eq 2 ]
  [[ "$(events)" == "empty curl empty restart " ]]
  [ "$(awk '{ print $1 }' "${WORK}/empty-calls" | sort -u)" = "true" ]
  [ "$(awk '{ print $3 }' "${WORK}/empty-calls" | tr '\n' ' ')" = "dll-${V1} dll-${V1} " ]
}

@test "players on at the first check: no download, no swap" {
  empty_seq 1
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V1}"
  [ "$(downloads)" -eq 0 ]
  [ "$(restarts)" -eq 0 ]
  [ ! -e "${STATE}/last-good" ]
}

@test "players joining during the download: nothing is swapped" {
  empty_seq 0 1
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V1}"
  [ "$(downloads)" -eq 1 ]
  [ "$(restarts)" -eq 0 ]
}

@test "an image without checkServerEmpty counts as a server that is not empty" {
  : >"${WORK}/common"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V1}"
  [ "$(downloads)" -eq 0 ]
  [ "$(restarts)" -eq 0 ]
  rm "${WORK}/common"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V1}"
  [ "$(restarts)" -eq 0 ]
}

@test "a server that is not RUNNING is left alone, so the pod start is not raced" {
  set_state enshrouded-server STOPPED
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V1}"
  [ "$(downloads)" -eq 0 ]
  [ "$(empty_checks)" -eq 0 ]
  [ "$(restarts)" -eq 0 ]
}

@test "a supervisor that does not answer is no reason to swap" {
  touch "${WORK}/sv-down"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V1}"
  [ "$(downloads)" -eq 0 ]
  [ "$(restarts)" -eq 0 ]
}

@test "skips the swap while the updater pidfile names a live process" {
  /usr/bin/sleep 97 >/dev/null 2>&1 3>&- &
  BG_PIDS+=("$!")
  echo "$!" >"${WORK}/updater.pid"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V1}"
  [ "$(downloads)" -eq 0 ]
  [ "$(restarts)" -eq 0 ]
  [ "$(<"${WORK}/updater.pid")" = "${BG_PIDS[0]}" ]
}

@test "a stale updater pidfile does not block the swap, and the script leaves the file alone" {
  echo "999999" >"${WORK}/updater.pid"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ "$(<"${WORK}/updater.pid")" = "999999" ]
}

@test "skips the swap while supervisorctl shows the updater RUNNING" {
  set_state enshrouded-updater RUNNING 555
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V1}"
  [ "$(downloads)" -eq 0 ]
  [ "$(restarts)" -eq 0 ]
}

@test "a run that finds another run holding the lock does nothing, and exits 0" {
  setsid flock -x "${WORK}/cron.lock" /usr/bin/sleep 97 >/dev/null 2>&1 3>&- &
  BG_PIDS+=("$!")
  local i
  for i in $(seq 1 50); do
    flock -n "${WORK}/cron.lock" true || break
    /usr/bin/sleep 0.1
  done
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V1}"
  [ "$(downloads)" -eq 0 ]
  [ "$(restarts)" -eq 0 ]
  [ "$(empty_checks)" -eq 0 ]
}

@test "restarts the server with a timeout that outlasts the 66 s it takes to stop" {
  run_cron
  [ "${status}" -eq 0 ]
  local secs
  secs="$(sed -n 's/^\([0-9][0-9]*\) supervisorctl restart enshrouded-server$/\1/p' "${WORK}/timeout-calls")"
  [ -n "${secs}" ]
  [ "${secs}" -ge 120 ]
}

@test "the 10 minute watch starts once the server is RUNNING again, however long the stop and start took" {
  echo 100 >"${WORK}/restart-secs"
  after_restart 1 "0|enshrouded-server|STARTING|" "60|enshrouded-server|RUNNING|950"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ "$(elapsed_since_restart_done 100)" -ge 660 ]
  [ "$(elapsed_since_restart_done 100)" -le 690 ]
  [ "$(restarts)" -eq 1 ]
}

@test "a crash 10 minutes after the server was RUNNING again is caught, though it needed a minute to start" {
  log_start 130
  log_fault 400
  after_restart 1 "0|enshrouded-server|STARTING|" "60|enshrouded-server|RUNNING|950" "650|enshrouded-server|FATAL|"
  run_cron
  [ "${status}" -eq 0 ]
  [ ! -e "${ROOT}/iphlpapi.dll" ]
  [ "$(<"${STATE}/bad-list")" = "${V2}" ]
}

@test "a server that survives the watch keeps the new release" {
  run_cron
  [ "${status}" -eq 0 ]
  [ "$(elapsed_since_restart_done)" -ge 600 ]
  [ "$(elapsed_since_restart_done)" -le 620 ]
  assert_installed "${V2}"
  [ ! -s "${STATE}/bad-list" ]
  [ "$(restarts)" -eq 1 ]
}

@test "a server that stops during the watch with a FAULT line gets the map turned off: the pair is bad-listed and the restart unloads it" {
  printf '{"finds":1}' >"${ROOT}/livemap/finds.json"
  log_start 70
  log_fault 150
  after_restart 1 "120|enshrouded-server|FATAL|"
  run_cron
  [ "${status}" -eq 0 ]
  [ ! -e "${ROOT}/iphlpapi.dll" ]
  [ "$(<"${ROOT}/livemap/finds.json")" = '{"finds":1}' ]
  [ "$(<"${STATE}/bad-list")" = "${V2}" ]
  [ "$(restarts)" -eq 2 ]
  [ ! -e "${STATE}/last-good" ]
  [[ "$(crash_line)" == "livemap-crash|version=${V2} build=${BUILD} dump=none count=1 decision=off fault=[livemap] FAULT "* ]]
}

@test "a server that restarted during the watch counts as a crash, judged on the run before the restart" {
  log_start 70
  log_fault 150
  log_start 190
  after_restart 1 "120|enshrouded-server|RUNNING|777"
  run_cron
  [ "${status}" -eq 0 ]
  [ ! -e "${ROOT}/iphlpapi.dll" ]
  [ "$(<"${STATE}/bad-list")" = "${V2}" ]
  [ "$(restarts)" -eq 2 ]
}

@test "a first crash during the watch without a FAULT line is reported and the map stays on" {
  after_restart 1 "120|enshrouded-server|RUNNING|777"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ ! -s "${STATE}/bad-list" ]
  [ "$(restarts)" -eq 1 ]
  [ "$(crash_line)" = "livemap-crash|version=${V2} build=${BUILD} dump=none count=1 decision=stays-on fault=none" ]
}

@test "a server that does not come back RUNNING after the restart is judged like any crash" {
  after_restart 1 "20|enshrouded-server|FATAL|"
  echo 1 >"${WORK}/restart-exit-1"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ ! -s "${STATE}/bad-list" ]
  [ "$(restarts)" -eq 1 ]
  [[ "$(crash_line)" == *"decision=stays-on fault=none" ]]
}

@test "a server that does not come back after the restart while the updater runs is no verdict either" {
  echo 1 >"${WORK}/restart-exit-1"
  echo "$((START + 100))|RUNNING|555" >>"${WORK}/sv/enshrouded-updater"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ ! -s "${STATE}/bad-list" ]
  [ "$(restarts)" -eq 1 ]
  [ "$(crash_count)" -eq 0 ]
}

@test "a crash in the last seconds of the watch is still caught, one after it is not" {
  log_start 70
  log_fault 650
  after_restart 1 "590|enshrouded-server|FATAL|"
  run_cron
  [ "${status}" -eq 0 ]
  [ ! -e "${ROOT}/iphlpapi.dll" ]
  [ "$(<"${STATE}/bad-list")" = "${V2}" ]
  rm -rf "${WORK}/sv" "${STATE}" "${WORK}/restart-count" "${WORK}/after-restart-1" "${WORK}/server-record"
  mkdir "${WORK}/sv"
  printf '0|RUNNING|100\n' >"${WORK}/sv/enshrouded-server"
  printf '0|EXITED|\n' >"${WORK}/sv/enshrouded-updater"
  install_by_hand "${V1}"
  after_restart 1 "640|enshrouded-server|FATAL|"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ ! -s "${STATE}/bad-list" ]
  [ "$(restarts)" -eq 1 ]
}

@test "after the map is turned off the same release is not downloaded again" {
  log_start 70
  log_fault 150
  after_restart 1 "120|enshrouded-server|FATAL|"
  run_cron
  [ "${status}" -eq 0 ]
  [ "$(downloads)" -eq 1 ]
  run_cron
  [ "${status}" -eq 0 ]
  [ ! -e "${ROOT}/iphlpapi.dll" ]
  [ "$(downloads)" -eq 1 ]
  [ "$(restarts)" -eq 2 ]
}

@test "a release is no worse for another release being bad-listed" {
  mkdir -p "${STATE}"
  printf '%s\n' "v1.9.0" "${V2}-rc1" "x${V2}" >"${STATE}/bad-list"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
}

@test "a bad-listed version is not downloaded or swapped, whatever the game build" {
  mkdir -p "${STATE}"
  echo "${V2}" >"${STATE}/bad-list"
  echo 26500000 >"${WORK}/current_version"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V1}"
  [ "$(downloads)" -eq 0 ]
  [ "$(restarts)" -eq 0 ]
}

@test "an updater run during the watch makes a failure inconclusive: the release stays, nothing is bad-listed, the updater is left to start the server" {
  log_start 70
  log_fault 150
  after_restart 1 "100|enshrouded-updater|RUNNING|555" "130|enshrouded-server|STOPPED|"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ ! -s "${STATE}/bad-list" ]
  [ "$(restarts)" -eq 1 ]
  [ "$(crash_count)" -eq 0 ]
}

@test "after an inconclusive watch the next run judges nothing and swaps nothing" {
  after_restart 1 "100|enshrouded-updater|RUNNING|555" "130|enshrouded-server|STOPPED|" "160|enshrouded-updater|EXITED|"
  run_cron
  [ "${status}" -eq 0 ]
  set_state enshrouded-server RUNNING 5
  set_state enshrouded-updater EXITED
  run_cron
  [ "${status}" -eq 0 ]
  [ "$(downloads)" -eq 1 ]
  [ "$(restarts)" -eq 1 ]
  assert_installed "${V2}"
  [ "$(crash_count)" -eq 0 ]
}

@test "a server that stops after the updater finished is a crash like any other" {
  after_restart 1 "100|enshrouded-updater|RUNNING|555" "110|enshrouded-updater|EXITED|" "130|enshrouded-server|FATAL|"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ ! -s "${STATE}/bad-list" ]
  [ "$(restarts)" -eq 1 ]
  [[ "$(crash_line)" == *"decision=stays-on fault=none" ]]
}

@test "a game update during the watch makes a failure inconclusive" {
  log_start 70
  log_fault 150
  echo 26500000 >"${WORK}/build-after-restart-1"
  after_restart 1 "120|enshrouded-server|FATAL|"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ ! -s "${STATE}/bad-list" ]
  [ "$(crash_count)" -eq 0 ]
}

@test "a short updater run next to a healthy server does not undo the swap" {
  after_restart 1 "100|enshrouded-updater|RUNNING|555" "110|enshrouded-updater|EXITED|"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ ! -s "${STATE}/bad-list" ]
  [ "$(restarts)" -eq 1 ]
}

@test "a release that cannot load the map (no live map) is no crash and stays in place" {
  log_line "2026-11-04 07:00:00.000 livemap 2.0.0 starting: Enabled=1 Port=15637 real iphlpapi loaded"
  log_line "2026-11-04 07:00:00.100 unknown server build (TimeDateStamp 1, SizeOfImage 0x1), not hooking; no live map"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ ! -s "${STATE}/bad-list" ]
  [ "$(restarts)" -eq 1 ]
  [ "$(crash_count)" -eq 0 ]
  [[ "$(status_line)" == "livemap-status|state=inactive version=2.0.0 build=${BUILD}" ]]
}

@test "the cron never writes livemap.ini, and creates none" {
  run_cron
  [ "${status}" -eq 0 ]
  [ ! -e "${ROOT}/livemap.ini" ]
  [ ! -e "${ROOT}/livemap.ini.new" ]
  printf '[livemap]\nKey=kept-key-1234\n' >"${ROOT}/livemap.ini"
  touch -d '2020-01-01 00:00:00' "${ROOT}/livemap.ini"
  local before
  before="$(stat -c '%Y %s' "${ROOT}/livemap.ini")"
  write_pin "${V1}"
  install_by_hand "${V2}"
  run_cron
  [ "${status}" -eq 0 ]
  [ "$(stat -c '%Y %s' "${ROOT}/livemap.ini")" = "${before}" ]
  [ "$(<"${ROOT}/livemap.ini")" = $'[livemap]\nKey=kept-key-1234' ]
}

@test "the cron reads the pin from the file only, never from the environment" {
  make_release v3.0.0
  run_cron LIVEMAP_VERSION=v3.0.0 LIVEMAP_SHA256="$(sha_of v3.0.0)" LIVEMAP_REPO=someone/else
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  grep -q 'github.com/anthony-spruyt/enshrouded-livemap/releases/download/v2.0.0/' "${WORK}/curl-calls"
  [ "$(downloads)" -eq 1 ]
  rm "${PINDIR}/livemap-pin.yaml"
  install_by_hand "${V1}"
  run_cron LIVEMAP_VERSION=v3.0.0 LIVEMAP_SHA256="$(sha_of v3.0.0)"
  [ "${status}" -eq 0 ]
  assert_installed "${V1}"
  [ "$(downloads)" -eq 1 ]
}

@test "a pin file with no version or hash is no pin" {
  printf '# renovate: depName=anthony-spruyt/enshrouded-livemap datasource=github-release-attachments digest=sha256\n' >"${PINDIR}/livemap-pin.yaml"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V1}"
  [ "$(downloads)" -eq 0 ]
  [ "$(restarts)" -eq 0 ]
}

@test "a failed download keeps the installed release and exits 0" {
  echo 22 >"${WORK}/curl-exit"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V1}"
  [ "$(restarts)" -eq 0 ]
  [ ! -s "${STATE}/bad-list" ]
}

@test "a download that does not match the pinned hash is never installed" {
  write_pin "${V2}" 0000000000000000000000000000000000000000000000000000000000000000
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V1}"
  [ "$(downloads)" -eq 1 ]
  [ "$(restarts)" -eq 0 ]
}

@test "a download that is no zip leaves the installed release alone" {
  echo "not a zip" >"${WORK}/served/${V2}.zip"
  write_pin "${V2}"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V1}"
  [ "$(restarts)" -eq 0 ]
}

@test "a swap that cannot copy the release leaves the old files and does not restart" {
  chmod -R a-w "${ROOT}/livemap"
  chmod a-w "${ROOT}"
  run_cron
  chmod -R u+w "${ROOT}"
  [ "${status}" -eq 0 ]
  [ "$(restarts)" -eq 0 ]
}

@test "with the map off the cron installs a newly pinned release like any swap" {
  rm "${ROOT}/iphlpapi.dll" "${ROOT}/livemap/.installed"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ "$(restarts)" -eq 1 ]
}

@test "failing restart commands still exit 0 and the map still ends up off" {
  log_start 15
  log_fault 18
  after_restart 1 "20|enshrouded-server|FATAL|"
  echo 1 >"${WORK}/restart-exit-1"
  echo 1 >"${WORK}/restart-exit-2"
  run_cron
  [ "${status}" -eq 0 ]
  [ ! -e "${ROOT}/iphlpapi.dll" ]
  [ "$(<"${STATE}/bad-list")" = "${V2}" ]
}

@test "logs a status line for the live map on every run" {
  log_line "2026-11-04 07:00:00.000 livemap 1.7.2 starting: Enabled=1 Port=15637 real iphlpapi loaded"
  write_pin "${V1}"
  run_cron
  [ "${status}" -eq 0 ]
  [[ "$(status_line)" =~ ${STATUS_RE} ]]
  [ "$(status_line)" = "livemap-status|state=active version=1.7.2 build=${BUILD}" ]
}

@test "logs the status line even when there is no pin, the updater is running or another run holds the lock" {
  rm "${PINDIR}/livemap-pin.yaml"
  run_cron
  [ "$(grep -c '^livemap-status|' "${WORK}/logger-calls")" -eq 1 ]
  write_pin "${V2}"
  set_state enshrouded-updater RUNNING 555
  run_cron
  [ "$(grep -c '^livemap-status|' "${WORK}/logger-calls")" -eq 2 ]
  set_state enshrouded-updater EXITED
  setsid flock -x "${WORK}/cron.lock" /usr/bin/sleep 97 >/dev/null 2>&1 3>&- &
  BG_PIDS+=("$!")
  local i
  for i in $(seq 1 50); do
    flock -n "${WORK}/cron.lock" true || break
    /usr/bin/sleep 0.1
  done
  run_cron
  [ "$(grep -c '^livemap-status|' "${WORK}/logger-calls")" -eq 3 ]
}

@test "the status is inactive with an unknown version when the log has no start line" {
  write_pin "${V1}"
  run_cron
  [ "$(status_line)" = "livemap-status|state=inactive version=unknown build=${BUILD}" ]
  log_line "2026-11-04 07:00:00.000 CHEST entity 1 verb 2 random-loot -1 position 1.0 2.0 3.0"
  run_cron
  [ "$(status_line)" = "livemap-status|state=inactive version=unknown build=${BUILD}" ]
}

@test "the status is inactive when the DLL logs that it hooks nothing, and the last of the log decides" {
  write_pin "${V1}"
  log_line "2026-11-04 07:00:00.000 livemap 1.7.0 starting: Enabled=1 Port=15637 real iphlpapi loaded"
  log_line "2026-11-04 07:00:00.100 unknown server build (TimeDateStamp 1, SizeOfImage 0x1), not hooking; no live map"
  run_cron
  [ "$(status_line)" = "livemap-status|state=inactive version=1.7.0 build=${BUILD}" ]
  log_line "2026-11-04 09:00:00.000 livemap 1.7.2 starting: Enabled=1 Port=15637 real iphlpapi loaded"
  run_cron
  [ "$(status_line)" = "livemap-status|state=active version=1.7.2 build=${BUILD}" ]
}

@test "the status is disabled when livemap.ini switches the map off" {
  write_pin "${V1}"
  log_line "2026-11-04 07:00:00.000 livemap 1.7.2 starting: Enabled=0 Port=15637 real iphlpapi loaded"
  log_line "2026-11-04 07:00:00.100 disabled in livemap.ini"
  run_cron
  [ "$(status_line)" = "livemap-status|state=disabled version=1.7.2 build=${BUILD}" ]
}

@test "the status build is unknown when the game build file is missing" {
  write_pin "${V1}"
  rm "${WORK}/current_version"
  run_cron
  [ "$(status_line)" = "livemap-status|state=inactive version=unknown build=unknown" ]
}

@test "a log line that only mentions the start or failure text does not change the status" {
  write_pin "${V1}"
  log_line "2026-11-04 07:00:00.000 livemap 1.7.2 starting: Enabled=1 Port=15637 real iphlpapi loaded"
  log_line "2026-11-04 07:00:01.000 JOINED name livemap 9.9.9 starting: x"
  log_line "2026-11-04 07:00:02.000 LEFT slot 0 note disabled in livemap.ini now"
  log_line "player said: livemap 9.9.9 starting: x"
  log_line "player said; no live map"
  run_cron
  [ "$(status_line)" = "livemap-status|state=active version=1.7.2 build=${BUILD}" ]
}

@test "no run logs the map key" {
  write_pin "${V1}"
  printf '[livemap]\nKey=mapkeymapkeymapkey\n' >"${ROOT}/livemap.ini"
  log_line "2026-11-04 07:00:00.000 livemap 1.7.2 starting: Enabled=1 Port=15637 real iphlpapi loaded"
  log_line "2026-11-04 07:00:01.000 announce key=mapkeymapkeymapkey"
  run_cron LIVEMAP_KEY=mapkeymapkeymapkey
  [ "${status}" -eq 0 ]
  run_cron
  [ -s "${WORK}/logger-calls" ]
  [ "$(grep -c 'mapkeymapkeymapkey' "${WORK}/logger-calls")" -eq 0 ]
  [[ "${output}" != *"mapkeymapkeymapkey"* ]]
}

@test "the bootstrap takes the pin from the file before the environment" {
  make_release v3.0.0
  run_boot LIVEMAP_VERSION=v3.0.0 LIVEMAP_SHA256="$(sha_of v3.0.0)"
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  grep -q 'github.com/anthony-spruyt/enshrouded-livemap/releases/download/v2.0.0/' "${WORK}/curl-calls"
}

@test "the bootstrap takes no pin from the environment, with or without a pin file" {
  rm "${PINDIR}/livemap-pin.yaml"
  make_release v3.0.0
  run_boot LIVEMAP_VERSION=v3.0.0 LIVEMAP_SHA256="$(sha_of v3.0.0)" LIVEMAP_REPO=anthony-spruyt/enshrouded-livemap
  [ "${status}" -eq 0 ]
  assert_installed "${V1}"
  [ "$(downloads)" -eq 0 ]
  printf 'LIVEMAP_VERSION: "%s"\n' "${V2}" >"${PINDIR}/livemap-pin.yaml"
  run_boot LIVEMAP_VERSION=v3.0.0 LIVEMAP_SHA256="$(sha_of v3.0.0)"
  [ "${status}" -eq 0 ]
  assert_installed "${V1}"
  [ "$(downloads)" -eq 0 ]
}

@test "the bootstrap installs without restarting or asking about players, and still writes livemap.ini" {
  run_boot
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ ! -e "${WORK}/supervisorctl-calls" ]
  [ ! -e "${WORK}/empty-calls" ]
  [ "$(head -n1 "${ROOT}/livemap.ini")" = "[livemap]" ]
}

@test "the bootstrap does not install a bad-listed version, but installs a newer pin" {
  mkdir -p "${STATE}"
  echo "${V2}" >"${STATE}/bad-list"
  rm "${ROOT}/iphlpapi.dll" "${ROOT}/livemap/.installed"
  run_boot
  [ "${status}" -eq 0 ]
  [ ! -e "${ROOT}/iphlpapi.dll" ]
  [ "$(downloads)" -eq 0 ]
  make_release v3.0.0
  write_pin v3.0.0
  run_boot
  [ "${status}" -eq 0 ]
  assert_installed v3.0.0
  [ "$(<"${STATE}/bad-list")" = "${V2}" ]
}

@test "the bootstrap adds the cron line, keeps the other lines and adds it once" {
  printf '*/30 * * * * /usr/local/sbin/enshrouded-updater >/dev/null 2>&1\n0 * * * * /usr/local/sbin/enshrouded-backup >/dev/null 2>&1\n' >"${WORK}/crontab"
  run_boot
  [ "${status}" -eq 0 ]
  run_boot
  [ "${status}" -eq 0 ]
  [ "$(grep -c 'livemap-install.sh --cron' "${WORK}/crontab")" -eq 1 ]
  grep -qxF '*/30 * * * * /usr/local/sbin/enshrouded-updater >/dev/null 2>&1' "${WORK}/crontab"
  grep -qxF '0 * * * * /usr/local/sbin/enshrouded-backup >/dev/null 2>&1' "${WORK}/crontab"
  [ "$(wc -l <"${WORK}/crontab")" -eq 3 ]
}

@test "the bootstrap leaves a crontab that already has the cron line untouched" {
  run_boot
  [ "${status}" -eq 0 ]
  [ "$(wc -l <"${WORK}/crontab-writes")" -eq 1 ]
  run_boot
  [ "${status}" -eq 0 ]
  [ "$(wc -l <"${WORK}/crontab-writes")" -eq 1 ]
}

@test "the cron line runs every 5 minutes off the updater's minutes, under a timeout, with its output dropped" {
  run_boot TZ=Australia/Melbourne
  [ "${status}" -eq 0 ]
  local line minutes minute
  line="$(grep 'livemap-install.sh --cron' "${WORK}/crontab")"
  [[ "${line}" =~ ^2-59/5\ \*\ \*\ \*\ \*\ TZ=[^\ ]+\ timeout\ [0-9]+\ bash\ /opt/livemap/livemap-install\.sh\ --cron\ \>/dev/null\ 2\>\&1$ ]]
  minutes="$(seq 2 5 59)"
  for minute in ${minutes}; do
    [ $((minute % 30)) -ne 0 ]
  done
}

@test "the bootstrap replaces an older cron line instead of adding a second" {
  printf '*/10 * * * * bash /opt/livemap/livemap-install.sh --cron\n' >"${WORK}/crontab"
  run_boot
  [ "${status}" -eq 0 ]
  [ "$(grep -c 'livemap-install.sh --cron' "${WORK}/crontab")" -eq 1 ]
  grep -q '^2-59/5 ' "${WORK}/crontab"
}

@test "the bootstrap adds the cron line again after the image rewrote the crontab" {
  run_boot
  printf '*/30 * * * * /usr/local/sbin/enshrouded-updater >/dev/null 2>&1\n' >"${WORK}/crontab"
  run_boot
  [ "${status}" -eq 0 ]
  [ "$(grep -c 'livemap-install.sh --cron' "${WORK}/crontab")" -eq 1 ]
}

@test "the cron line is added when the download fails and when there is no pin" {
  echo 22 >"${WORK}/curl-exit"
  run_boot
  [ "${status}" -eq 0 ]
  [ "$(grep -c 'livemap-install.sh --cron' "${WORK}/crontab")" -eq 1 ]
  rm "${WORK}/crontab" "${PINDIR}/livemap-pin.yaml"
  run_boot
  [ "${status}" -eq 0 ]
  [ "$(grep -c 'livemap-install.sh --cron' "${WORK}/crontab")" -eq 1 ]
}

@test "a crontab that cannot be edited does not stop the install or the exit 0" {
  touch "${WORK}/crontab-broken"
  run_boot
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ "$(head -n1 "${ROOT}/livemap.ini")" = "[livemap]" ]
}

@test "the pin file is plain KEY: \"value\" lines that Renovate's annotated-release manager reads" {
  run python3 -I - "${PIN_FILE}" <<'PY'
import re
import sys

text = open(sys.argv[1]).read()
manager = re.compile(
    r'#\s*renovate:\s*depName=(?P<depName>\S+)\s+datasource=github-release-attachments\s+digest=sha256\n'
    r'\s*\w+:[ \t]+"(?P<currentValue>[^"\s]+)"\n'
    r'\s*\w+:[ \t]+"(?P<currentDigest>[a-f0-9]{64})"'
)
m = manager.search(text)
assert m, "Renovate's manager does not match the pin file"
fields = dict(re.findall(r'^(LIVEMAP_[A-Z0-9_]+): "([^"]*)"', text, re.M))
assert m["currentValue"] == fields["LIVEMAP_VERSION"]
assert m["currentDigest"] == fields["LIVEMAP_SHA256"]
print(m["depName"], m["currentValue"])
PY
  echo "${output}"
  [ "${status}" -eq 0 ]
}

@test "the cron downloads the version in the committed pin file from the fork" {
  local repo version
  cp "${PIN_FILE}" "${PINDIR}/livemap-pin.yaml"
  repo="$(sed -n 's/^repo=\(.*\)$/\1/p' "${SCRIPT}")"
  version="$(sed -n 's/^LIVEMAP_VERSION: *"\([^"]*\)".*/\1/p' "${PIN_FILE}")"
  run_cron
  [ "${status}" -eq 0 ]
  grep -qF "github.com/${repo}/releases/download/${version}/EnshroudedLiveMap-${version#v}.zip" "${WORK}/curl-calls"
}

@test "the pin is no longer env in values.yaml" {
  run grep -c -E 'LIVEMAP_(REPO|VERSION|SHA256)' "${VALUES}"
  [ "${output}" = "0" ]
}

@test "the pin file reaches the pod as a ConfigMap directory mount that updates in place" {
  run python3 -I - "${VALUES}" "${KUSTOMIZATION}" <<'PY'
import sys
import yaml

values = yaml.safe_load(open(sys.argv[1]))
kustomization = yaml.safe_load(open(sys.argv[2]))
gen = next(g for g in kustomization["configMapGenerator"] if g["name"] == "enshrouded-livemap-pin")
assert gen["options"]["disableNameSuffixHash"] is True, "a hashed name would roll the pod on every pin bump"
assert gen["files"] == ["livemap-pin.yaml"]
vol = values["persistence"]["livemap-pin"]
assert vol["type"] == "configMap"
assert vol["name"] == gen["name"]
mounts = vol["advancedMounts"]["enshrouded"]["app"]
assert [m["path"] for m in mounts] == ["/opt/livemap-pin"], "a subPath mount never updates"
assert all("subPath" not in m for m in mounts)
assert all(m.get("readOnly") for m in mounts)
PY
  echo "${output}"
  [ "${status}" -eq 0 ]
}

@test "Flux leaves the pin ConfigMap as it is, whatever the pin file holds" {
  run python3 -I - "${KUSTOMIZATION}" <<'PY'
import sys
import yaml

kustomization = yaml.safe_load(open(sys.argv[1]))
gen = next(g for g in kustomization["configMapGenerator"] if g["name"] == "enshrouded-livemap-pin")
annotations = gen["options"].get("annotations", {})
assert annotations.get("kustomize.toolkit.fluxcd.io/substitute") == "disabled"
PY
  echo "${output}"
  [ "${status}" -eq 0 ]
}

@test "the script reads the pin from the directory the ConfigMap is mounted at" {
  local read_from mount
  read_from="$(sed -n 's/^pin_dir=\$(override LIVEMAP_PIN_DIR \(\/[^ )]*\))$/\1/p' "${SCRIPT}")"
  mount="$(python3 -I -c 'import sys, yaml
v = yaml.safe_load(open(sys.argv[1]))
print(v["persistence"]["livemap-pin"]["advancedMounts"]["enshrouded"]["app"][0]["path"])' "${VALUES}")"
  [ -n "${read_from}" ]
  [ "${read_from}" = "${mount}" ]
}

@test "Reloader rolls the pod for the secrets it reads and for no ConfigMap" {
  run python3 -I - "${VALUES}" <<'PY'
import sys
import yaml

values = yaml.safe_load(open(sys.argv[1]))
controller = values["controllers"]["enshrouded"]
annotations = controller.get("annotations", {})
assert "reloader.stakater.com/auto" not in annotations, "auto also rolls the pod for the pin ConfigMap"
assert "configmap.reloader.stakater.com/reload" not in annotations
listed = sorted(annotations["secret.reloader.stakater.com/reload"].split(","))
app = controller["containers"]["app"]
used = {f["secretRef"]["name"] for f in app.get("envFrom", []) if "secretRef" in f}
for value in app.get("env", {}).values():
    if isinstance(value, dict):
        ref = value.get("valueFrom", {}).get("secretKeyRef")
        if ref:
            used.add(ref["name"])
assert listed == sorted(used), f"listed {listed}, read {sorted(used)}"
PY
  echo "${output}"
  [ "${status}" -eq 0 ]
}

@test "last-good and the bad list live on a volume that survives a pod restart" {
  local state
  state="$(sed -n 's/^state=\$(override LIVEMAP_STATE_DIR \(\/[^ )]*\))$/\1/p' "${SCRIPT}")"
  [ -n "${state}" ]
  run python3 -I - "${VALUES}" "${state}" <<'PY'
import sys
import yaml

values = yaml.safe_load(open(sys.argv[1]))
state = sys.argv[2]
paths = [
    m["path"]
    for vol in values["persistence"].values()
    if "existingClaim" in vol
    for m in vol["advancedMounts"]["enshrouded"]["app"]
    if "subPath" not in m
]
assert any(state.startswith(p + "/") for p in paths), f"{state} is not under a PVC mount: {paths}"
PY
  echo "${output}"
  [ "${status}" -eq 0 ]
}

@test "the cron line runs the script where the script ConfigMap is mounted" {
  local called mount
  called="$(grep -o 'bash /[^ ]*livemap-install.sh --cron' "${SCRIPT}" | head -n1 | cut -d' ' -f2)"
  mount="$(python3 -I -c 'import sys, yaml
v = yaml.safe_load(open(sys.argv[1]))
print(v["persistence"]["livemap-script"]["advancedMounts"]["enshrouded"]["app"][0]["path"])' "${VALUES}")"
  [ -n "${called}" ]
  [ "${called}" = "${mount}/livemap-install.sh" ]
}

@test "the livemap alerts count only the status line the script logs, at the start of the line" {
  grep -q -e '-t livemap-status' "${SCRIPT}"
  grep -q '\./livemap.yaml' "${VMRULES}/kustomization.yaml"
  run python3 -I - "${VMRULES}/livemap.yaml" <<'PY'
import re
import sys
import yaml

rule = yaml.safe_load(open(sys.argv[1]))
groups = rule["spec"]["groups"]
assert all(g["type"] == "vlogs" for g in groups)
alerts = {r["alert"]: (g, r) for g in groups for r in g["rules"]}
group, inactive_rule = alerts["LivemapInactive"]
assert inactive_rule["for"] == "4h"
assert inactive_rule["labels"]["owned_by"] == "workflow"


def counts(expr, name, line):
    clause = re.search(r"count\(\) if \(((?:(?!count\(\)).)*?)\) as " + name + r"\b", expr, re.S).group(1)
    filters = re.findall(r"(-?)_msg:~`([^`]*)`", clause)
    rest = re.sub(r"-?_msg:~`[^`]*`", "", clause)
    assert not rest.strip(), "only anchored _msg regexes are modelled here: " + rest
    return all(bool(re.search(rx, line)) != bool(neg) for neg, rx in filters)


stamp = "2026-11-04 23:30:01.123"
fields = " version=v1.0.0 build=26404334"
expr = inactive_rule["expr"]
for state, want_active, want_inactive in [
    ("active", True, False),
    ("inactive", False, True),
    ("disabled", False, True),
    ("off", False, True),
]:
    line = f"{stamp} livemap-status: state={state}{fields}"
    assert counts(expr, "active", line) is want_active, line
    assert counts(expr, "inactive", line) is want_inactive, line
for text in [
    "livemap-status: state=active",
    f"{stamp} [chat] Someone: livemap-status: state=active{fields}",
    f"{stamp} [chat] Someone: livemap-status: state=inactive{fields}",
    f"[2026-11-04 23:30:01] livemap-status: state=active{fields}",
    f"{stamp} livemap-crash: version=v1.0.0 decision=off fault=livemap-status: state=active",
]:
    assert not counts(expr, "active", text), text
    assert not counts(expr, "inactive", text), text

group, missing = alerts["LivemapStatusMissing"]
assert group["interval"] == "30m"
assert counts(missing["expr"], "status_lines", f"{stamp} livemap-status: state=active{fields}")
for text in [
    f"{stamp} [chat] Someone: livemap-status: state=active{fields}",
    f"[2026-11-04 23:30:01] livemap-status: state=active{fields}",
]:
    assert not counts(missing["expr"], "status_lines", text), text
PY
  echo "${output}"
  [ "${status}" -eq 0 ]
}

@test "the missing status alert looks at the game container only" {
  run python3 -I - "${VMRULES}/livemap.yaml" <<'PY'
import re
import sys
import yaml

rule = yaml.safe_load(open(sys.argv[1]))
rules = {r["alert"]: r for g in rule["spec"]["groups"] for r in g["rules"]}
selector = re.match(r"\s*\{([^}]*)\}", rules["LivemapStatusMissing"]["expr"]).group(1)
assert '"kubernetes.pod_namespace"="enshrouded"' in selector
assert '"kubernetes.container_name"="app"' in selector, "a pod without the game container would raise the alert"
PY
  echo "${output}"
  [ "${status}" -eq 0 ]
}

@test "the CI runs these tests when the pin file changes and does not validate it as a Kubernetes manifest" {
  grep -qF "app/livemap-pin.yaml'" <(sed -n '/^  changes:/,/^  kubeconform:/p' "${CI_REPO}")
  grep -qF "vmrules/livemap.yaml'" <(sed -n '/^  changes:/,/^  kubeconform:/p' "${CI_REPO}")
  grep -qF "! -name 'livemap-pin.yaml'" <(sed -n '/^  kubeconform:/,/^  kyverno-test:/p' "${CI_REPO}")
}

@test "the first run after a pod start only records the server, and a new pid at the next run is a crash with a full report" {
  write_pin "${V1}"
  run_cron
  [ "${status}" -eq 0 ]
  [ "$(crash_count)" -eq 0 ]
  read -r pid started seen build offset <"${WORK}/server-record"
  [ "${pid}" = 100 ]
  [ "${started}" -eq 0 ]
  [ "${seen}" = "${START}" ]
  [ "${build}" = "${BUILD}" ]
  crash_server 201
  run_cron
  [ "${status}" -eq 0 ]
  [ "$(crash_line)" = "livemap-crash|version=${V1} build=${BUILD} dump=none count=1 decision=stays-on fault=none" ]
  assert_installed "${V1}"
  [ "$(restarts)" -eq 0 ]
  read -r pid started seen build offset <"${WORK}/server-record"
  [ "${pid}" = 201 ]
  run_cron
  [ "$(crash_count)" -eq 1 ]
}

@test "a server restarted under the same pid is a crash too, a small drift in the start time is not" {
  echo "0|RUNNING|100|$((START - 1000))" >"${WORK}/sv/enshrouded-server"
  write_pin "${V1}"
  run_cron
  advance 300
  echo "$(<"${WORK}/clock")|RUNNING|100|$((START - 980))" >>"${WORK}/sv/enshrouded-server"
  run_cron
  [ "$(crash_count)" -eq 0 ]
  advance 300
  echo "$(<"${WORK}/clock")|RUNNING|100|$(($(<"${WORK}/clock") - 5))" >>"${WORK}/sv/enshrouded-server"
  run_cron
  [ "$(crash_count)" -eq 1 ]
  advance 300
  echo "$(<"${WORK}/clock")|RUNNING|100|$(($(<"${WORK}/clock") - 400))" >>"${WORK}/sv/enshrouded-server"
  run_cron
  [ "$(crash_count)" -eq 2 ]
}

@test "a new pid is a crash even when the start time looks the same" {
  echo "0|RUNNING|100|$((START - 1000))" >"${WORK}/sv/enshrouded-server"
  write_pin "${V1}"
  run_cron
  advance 300
  echo "$(<"${WORK}/clock")|RUNNING|555|$((START - 1000))" >>"${WORK}/sv/enshrouded-server"
  run_cron
  [ "$(crash_count)" -eq 1 ]
}

@test "a crash dump older than the last run is not reported" {
  write_pin "${V1}"
  mkdir -p "${ROOT}/crash_dumps"
  : >"${ROOT}/crash_dumps/old.dmp"
  touch -d "@$((START - 5000))" "${ROOT}/crash_dumps/old.dmp"
  run_cron
  crash_server 201
  run_cron
  [ "$(crash_line)" = "livemap-crash|version=${V1} build=${BUILD} dump=none count=1 decision=stays-on fault=none" ]
}

@test "a crash with a FAULT line from the run that crashed turns the map off and unloads it" {
  write_pin "${V1}"
  log_start
  log_fault
  log_start 290
  run_cron
  crash_server 201
  run_cron
  [ "${status}" -eq 0 ]
  [ ! -e "${ROOT}/iphlpapi.dll" ]
  [ "$(<"${STATE}/bad-list")" = "${V1}" ]
  [ -f "${ROOT}/livemap/index.html" ]
  [ "$(restarts)" -eq 1 ]
  [ "$(awk '{ print $1 }' "${WORK}/empty-calls" | sort -u)" = "true" ]
  [ "$(crash_line)" = "livemap-crash|version=${V1} build=${BUILD} dump=none count=1 decision=off fault=[livemap] FAULT code=0xc0000005 at=livemap+0x1a2b site=movement" ]
  run_cron
  [ "$(status_line)" = "livemap-status|state=off version=1.0.0 build=${BUILD}" ]
}

@test "a server that is down is judged on the run it was up in when it was last seen" {
  write_pin "${V1}"
  log_start
  log_fault
  run_cron
  set_state enshrouded-server FATAL
  advance 300
  run_cron
  [ ! -e "${ROOT}/iphlpapi.dll" ]
  [[ "$(crash_line)" == *"decision=off fault=[livemap] FAULT code="* ]]
}

@test "a FAULT line from an earlier run or from the run that is up now does not count" {
  write_pin "${V1}"
  log_start -900
  log_fault -800
  log_start
  log_start 290
  log_fault 295
  run_cron
  crash_server 201
  run_cron
  assert_installed "${V1}"
  [ "$(crash_line)" = "livemap-crash|version=${V1} build=${BUILD} dump=none count=1 decision=stays-on fault=none" ]
}

@test "text that only looks like a FAULT line never counts, and lines with the key or the announce text are never read" {
  write_pin "${V1}"
  log_start
  log_line "2026-11-04 07:00:01.000 JOINED name [livemap] FAULT code=1"
  log_line "[livemap] FAULT code=2 from a player"
  log_line "player said [livemap] FAULT code=9"
  log_line "2026-11-04 07:00:02.000 [livemap] FAULT code=3 announce key=mapkeymapkeymapkey"
  log_line "2026-11-04 07:00:03.000 [livemapx] FAULT code=4"
  log_start 290
  run_cron
  crash_server 201
  run_cron
  assert_installed "${V1}"
  [ "$(crash_line)" = "livemap-crash|version=${V1} build=${BUILD} dump=none count=1 decision=stays-on fault=none" ]
  rm -f "${STATE}/crashes"
  log_line "2026-11-04 07:00:04.000 [livemap] FAULT code=0xc0000005 at=livemap+0x1 key=mapkeymapkeymapkey"
  log_line "2026-11-04 07:00:05.000 [livemap] FAULT code=7 ANNOUNCE"
  log_line "2026-11-04 07:00:06.000 [livemap] FAULT code=8 Key=zzz"
  log_start 590
  crash_server 202
  run_cron
  [ "$(grep -c 'mapkeymapkeymapkey' "${WORK}/logger-calls")" -eq 0 ]
  [ "$(grep -c -i 'announce' "${WORK}/logger-calls")" -eq 0 ]
  assert_installed "${V1}"
}

@test "a FAULT line is cut to 200 characters and a line break cannot add a second log line" {
  write_pin "${V1}"
  log_start
  log_line "2026-11-04 07:05:00.000 [livemap] FAULT $(printf '\001')$(printf 'x%.0s' $(seq 1 300))"
  log_start 290
  run_cron
  crash_server 201
  run_cron
  [ "$(crash_line | sed 's/.*fault=//' | wc -c)" -le 202 ]
  [ "$(grep -c '^livemap-crash|' "${WORK}/logger-calls")" -eq 1 ]
  [ "$(LC_ALL=C grep -c "$(printf '\001')" "${WORK}/logger-calls")" -eq 0 ]
}

@test "a second crash of the same version within 24 hours turns the map off without a FAULT line" {
  write_pin "${V1}"
  run_cron
  crash_server 201
  run_cron
  assert_installed "${V1}"
  advance 3600
  crash_server 202
  run_cron
  [ ! -e "${ROOT}/iphlpapi.dll" ]
  [ "$(<"${STATE}/bad-list")" = "${V1}" ]
  [ "$(crash_line)" = "livemap-crash|version=${V1} build=${BUILD} dump=none count=2 decision=off fault=none" ]
  [ "$(restarts)" -eq 1 ]
}

@test "crashes of another version or more than 24 hours old do not count" {
  write_pin "${V1}"
  mkdir -p "${STATE}"
  printf '%s %s\n' $((START - 90000)) "${V1}" $((START - 100)) "${V2}" >"${STATE}/crashes"
  run_cron
  crash_server 201
  run_cron
  assert_installed "${V1}"
  [ "$(crash_line)" = "livemap-crash|version=${V1} build=${BUILD} dump=none count=1 decision=stays-on fault=none" ]
  [ "$(wc -l <"${STATE}/crashes")" -eq 2 ]
  [ "$(grep -c "^$((START - 90000)) " "${STATE}/crashes")" -eq 0 ]
}

@test "a crash report names the new crash dump and not an old one, and a dump alone turns nothing off" {
  write_pin "${V1}"
  mkdir -p "${ROOT}/crash_dumps"
  : >"${ROOT}/crash_dumps/old.dmp"
  touch -d "@$((START - 5000))" "${ROOT}/crash_dumps/old.dmp"
  run_cron
  : >"${ROOT}/crash_dumps/new one.dmp"
  touch -d "@$((START + 200))" "${ROOT}/crash_dumps/new one.dmp"
  crash_server 201
  run_cron
  [ "$(crash_line)" = "livemap-crash|version=${V1} build=${BUILD} dump=newone.dmp count=1 decision=stays-on fault=none" ]
  assert_installed "${V1}"
}

@test "a run that handled a crash does not swap" {
  run_cron
  [ "$(restarts)" -eq 1 ]
  crash_server 201
  make_release v3.0.0
  write_pin v3.0.0
  run_cron
  [ "$(crash_count)" -eq 1 ]
  [ "$(downloads)" -eq 1 ]
  [ "$(restarts)" -eq 1 ]
}

@test "the map stays loaded while players are on and goes at the next restart" {
  write_pin "${V1}"
  log_start
  log_fault
  log_start 290
  run_cron
  empty_seq 1
  crash_server 201
  run_cron
  [ ! -e "${ROOT}/iphlpapi.dll" ]
  [ "$(<"${STATE}/bad-list")" = "${V1}" ]
  [ "$(restarts)" -eq 0 ]
}

@test "turning the map off twice lists the version once, and a crash with no map installed is not reported" {
  write_pin "${V1}"
  mkdir -p "${STATE}"
  echo "${V1}" >"${STATE}/bad-list"
  log_start
  log_fault
  log_start 290
  run_cron
  crash_server 201
  run_cron
  [ "$(wc -l <"${STATE}/bad-list")" -eq 1 ]
  [ ! -e "${ROOT}/iphlpapi.dll" ]
  crash_server 202
  run_cron
  [ "$(crash_count)" -eq 1 ]
}

@test "a newer pin installs after the map was turned off and the bad version stays listed" {
  write_pin "${V1}"
  log_start
  log_fault
  log_start 290
  run_cron
  crash_server 201
  run_cron
  [ ! -e "${ROOT}/iphlpapi.dll" ]
  run_cron
  [ "$(downloads)" -eq 0 ]
  write_pin "${V2}"
  run_cron
  assert_installed "${V2}"
  [ "$(<"${STATE}/bad-list")" = "${V1}" ]
}

@test "an updater, a helper or a game update next to a new pid is planned and never counts" {
  write_pin "${V1}"
  run_cron
  set_state enshrouded-updater RUNNING 555
  crash_server 201
  run_cron
  [ "$(crash_count)" -eq 0 ]
  set_state enshrouded-updater EXITED
  crash_server 202
  run_cron
  [ "$(crash_count)" -eq 1 ]
  echo 26500000 >"${WORK}/current_version"
  crash_server 203
  run_cron
  [ "$(crash_count)" -eq 1 ]
  echo "$(<"${WORK}/clock")|RUNNING|600" >>"${WORK}/sv/enshrouded-restart"
  crash_server 204
  run_cron
  [ "$(crash_count)" -eq 1 ]
  advance 300
  echo "$(<"${WORK}/clock")|EXITED|" >>"${WORK}/sv/enshrouded-restart"
  crash_server 205
  run_cron
  [ "$(crash_count)" -eq 1 ]
  [ ! -s "${STATE}/bad-list" ]
}

@test "a live updater pidfile makes a new pid planned" {
  write_pin "${V1}"
  run_cron
  /usr/bin/sleep 97 >/dev/null 2>&1 3>&- &
  BG_PIDS+=("$!")
  echo "$!" >"${WORK}/updater.pid"
  crash_server 201
  run_cron
  [ "$(crash_count)" -eq 0 ]
}

@test "a helper that ran before the last run does not excuse a crash" {
  write_pin "${V1}"
  set_state enshrouded-reset-roles EXITED
  run_cron
  crash_server 201
  run_cron
  [ "$(crash_count)" -eq 1 ]
}

@test "a server that fell over after it was up is a crash once per container" {
  write_pin "${V1}"
  run_cron
  set_state enshrouded-server BACKOFF
  advance 300
  run_cron
  [ "$(crash_count)" -eq 1 ]
  [ ! -e "${WORK}/server-record" ]
  advance 300
  run_cron
  [ "$(crash_count)" -eq 1 ]
}

@test "the bootstrap forgets the recorded server, so a pod start is never a crash" {
  write_pin "${V1}"
  run_cron
  [ -f "${WORK}/server-record" ]
  run_boot
  [ ! -e "${WORK}/server-record" ]
  crash_server 201
  run_cron
  [ "$(crash_count)" -eq 0 ]
}

@test "the marker of the older installer, with only the hash, names the pinned version when the hash matches" {
  write_pin "${V1}"
  sha_of "${V1}" >"${ROOT}/livemap/.installed"
  run_cron
  crash_server 201
  run_cron
  [[ "$(crash_line)" == "livemap-crash|version=${V1} "* ]]
  printf 'deadbeef\n' >"${ROOT}/livemap/.installed"
  crash_server 202
  run_cron
  [[ "$(crash_line)" == "livemap-crash|version=unknown "* ]]
}

@test "the status says off while the DLL is not installed, whatever the log says" {
  write_pin "${V1}"
  log_line "2026-11-04 07:00:00.000 livemap 1.7.2 starting: Enabled=1 Port=15637 real iphlpapi loaded"
  rm "${ROOT}/iphlpapi.dll"
  run_cron
  [[ "$(status_line)" =~ ${STATUS_RE} ]]
  [ "$(status_line)" = "livemap-status|state=off version=1.7.2 build=${BUILD}" ]
}

@test "each restart job of the image is planned while it starts, runs or stops, and once it ended" {
  write_pin "${V1}"
  run_cron
  local prog state pid=300
  for prog in enshrouded-restart enshrouded-force-update enshrouded-reset-roles; do
    for state in RUNNING STARTING STOPPING; do
      echo "$(<"${WORK}/clock")|${state}|600" >>"${WORK}/sv/${prog}"
      crash_server $((pid++))
      run_cron
      echo "$(<"${WORK}/clock")|EXITED|" >>"${WORK}/sv/${prog}"
      advance 120
      run_cron
    done
    echo "$(<"${WORK}/clock")|EXITED|" >>"${WORK}/sv/${prog}"
    crash_server $((pid++))
    run_cron
    advance 120
    run_cron
  done
  [ "$(crash_count)" -eq 0 ]
}

@test "a restart job that ended within the minute after the last run still excuses a new pid" {
  write_pin "${V1}"
  run_cron
  advance 20
  echo "$(<"${WORK}/clock")|EXITED|" >>"${WORK}/sv/enshrouded-restart"
  crash_server 201
  run_cron
  [ "$(crash_count)" -eq 0 ]
}

@test "the bootstrap puts the container's TZ into the cron line, because supervisord prints its times in it" {
  run_boot TZ=Australia/Melbourne
  [ "${status}" -eq 0 ]
  [ "$(grep -c 'livemap-install.sh --cron' "${WORK}/crontab")" -eq 1 ]
  grep -q '^2-59/5 \* \* \* \* TZ=Australia/Melbourne timeout [0-9]* bash /opt/livemap/livemap-install.sh --cron' "${WORK}/crontab"
}

@test "the cron line follows the TZ of the container and is written again when it changes" {
  run_boot TZ=Australia/Melbourne
  run_boot TZ=Europe/Paris
  [ "${status}" -eq 0 ]
  [ "$(grep -c 'livemap-install.sh --cron' "${WORK}/crontab")" -eq 1 ]
  grep -q ' TZ=Europe/Paris timeout ' "${WORK}/crontab"
}

@test "a TZ that is no zone name never reaches the cron line" {
  run_boot 'TZ=UTC; touch /tmp/never'
  [ "${status}" -eq 0 ]
  [ "$(grep -c 'livemap-install.sh --cron' "${WORK}/crontab")" -eq 1 ]
  [ "$(grep -c 'touch' "${WORK}/crontab")" -eq 0 ]
  grep -q '^2-59/5 \* \* \* \* timeout ' "${WORK}/crontab"
}

@test "a restart job that ended hours before the last run does not excuse a crash" {
  write_pin "${V1}"
  run_boot TZ=Australia/Melbourne
  echo "$(($(<"${WORK}/clock") - 7200))|EXITED|" >>"${WORK}/sv/enshrouded-restart"
  run_cron
  crash_server 201
  run_cron
  [ "$(crash_count)" -eq 1 ]
}

@test "a restart job that ended in December does not excuse a crash on 2 January" {
  echo 1798851600 >"${WORK}/clock"
  write_pin "${V1}"
  run_boot TZ=Australia/Melbourne
  echo "$(($(<"${WORK}/clock") - 3 * 86400))|EXITED|" >>"${WORK}/sv/enshrouded-restart"
  run_cron
  crash_server 201
  run_cron
  [ "$(crash_count)" -eq 1 ]
}

@test "a restart job that ended seconds after the last run excuses a crash, in the zone the cron line carries" {
  write_pin "${V1}"
  run_boot TZ=Australia/Melbourne
  run_cron
  advance 20
  echo "$(<"${WORK}/clock")|EXITED|" >>"${WORK}/sv/enshrouded-restart"
  crash_server 201
  run_cron
  [ "$(crash_count)" -eq 0 ]
}

@test "only a version shaped vX.Y.Z installs, in the cron run and in the bootstrap, and a bad-listed version cannot be re-spelled" {
  local v
  mkdir -p "${STATE}"
  echo "${V2}" >"${STATE}/bad-list"
  for v in "${V2}-rc1" "${V2}.1" "${V2}#x" "${V2}/../${V2}" "2.0.0" "v2.0" "v2.0.0 " "v2.0.0%2f" "../v2.0.0"; do
    write_pin "${v}" "$(sha_of "${V2}")"
    run_cron
    [ "${status}" -eq 0 ]
    run_boot
    [ "${status}" -eq 0 ]
    assert_installed "${V1}"
    [ "$(downloads)" -eq 0 ]
    [ "$(restarts)" -eq 0 ]
  done
  rm "${STATE}/bad-list"
  write_pin "${V2}/../${V2}" "$(sha_of "${V2}")"
  run_cron
  [ "$(downloads)" -eq 0 ]
}

@test "only a lowercase 64 digit hex hash installs" {
  local h
  for h in "$(sha_of "${V2}" | tr 'a-f' 'A-F')" "$(sha_of "${V2}" | cut -c 1-63)" "$(sha_of "${V2}")0" "$(sha_of "${V2}") extra" "$(sha_of "${V2}")  ../x" "${V2}"; do
    write_pin "${V2}" "${h}"
    run_cron
    [ "${status}" -eq 0 ]
    run_boot
    [ "${status}" -eq 0 ]
    assert_installed "${V1}"
    [ "$(downloads)" -eq 0 ]
  done
}

@test "a pin value that is not accepted is logged with a fixed message that never repeats the value" {
  write_pin "${V2}/../evil-version" "ABCDEF-evil-hash"
  run_boot
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"livemap-install: the pinned version is not shaped vX.Y.Z, ignoring it"* ]]
  [[ "${output}" == *"livemap-install: the pinned hash is not 64 lowercase hex digits, ignoring it"* ]]
  [[ "${output}" != *"evil"* ]]
  run_cron
  grep -q '^livemap-install|the pinned version is not shaped vX.Y.Z, ignoring it$' "${WORK}/logger-calls"
  [ "$(grep -c 'evil' "${WORK}/logger-calls")" -eq 0 ]
}

@test "the download always comes from the fork, whatever repo the pin file or the environment names" {
  printf 'LIVEMAP_REPO: "someone/else"\nLIVEMAP_VERSION: "%s"\nLIVEMAP_SHA256: "%s"\n' "${V2}" "$(sha_of "${V2}")" >"${PINDIR}/livemap-pin.yaml"
  run_cron LIVEMAP_REPO=another/one
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ "$(downloads)" -eq 1 ]
  grep -q 'https://github.com/anthony-spruyt/enshrouded-livemap/releases/download/v2.0.0/EnshroudedLiveMap-2.0.0.zip' "${WORK}/curl-calls"
  [ "$(grep -c -e 'someone' -e 'another' -e 'oggii' "${WORK}/curl-calls")" -eq 0 ]
  install_by_hand "${V1}"
  run_boot LIVEMAP_REPO=another/one
  assert_installed "${V2}"
  [ "$(grep -c -e 'someone' -e 'another' -e 'oggii' "${WORK}/curl-calls")" -eq 0 ]
}

@test "the pin file names no repo, and Renovate bumps the repo the script downloads from" {
  [ "$(grep -c 'LIVEMAP_REPO' "${PIN_FILE}")" -eq 0 ]
  [ "$(grep -c 'LIVEMAP_REPO' "${SCRIPT}")" -eq 0 ]
  [ "$(grep -c 'oggii' "${SCRIPT}")" -eq 0 ]
  local dep repo
  dep="$(sed -n 's/^# renovate: depName=\([^ ]*\) .*/\1/p' "${PIN_FILE}")"
  repo="$(sed -n 's/^repo=\(.*\)$/\1/p' "${SCRIPT}")"
  [ -n "${repo}" ]
  [ "${dep}" = "${repo}" ]
}

@test "a restart nobody planned is a crash when supervisord logged the server exiting, and none when it only logged a stop" {
  write_pin "${V1}"
  run_cron
  sv_log stopped
  crash_server 201
  run_cron
  [ "$(crash_count)" -eq 0 ]
  sv_log exited
  sv_log stopped
  crash_server 202
  run_cron
  [ "$(crash_count)" -eq 1 ]
}

@test "only the server's own lines in supervisord.log decide, and only those written since the last run" {
  write_pin "${V1}"
  sv_log exited
  run_cron
  sv_log exited enshrouded-updater
  sv_log stopped
  crash_server 201
  run_cron
  [ "$(crash_count)" -eq 0 ]
  sv_log stopped enshrouded-updater
  crash_server 202
  run_cron
  [ "$(crash_count)" -eq 1 ]
}

@test "a server that exited and is still down after it was up is a crash once" {
  write_pin "${V1}"
  run_cron
  set_state enshrouded-server EXITED
  advance 300
  run_cron
  [ "$(crash_count)" -eq 1 ]
  advance 300
  run_cron
  [ "$(crash_count)" -eq 1 ]
}

@test "a supervisord.log that was cut since the last run or is missing is no evidence, and the new pid is judged as before" {
  write_pin "${V1}"
  sv_log stopped
  run_cron
  : >"${WORK}/supervisord.log"
  crash_server 201
  run_cron
  [ "$(crash_count)" -eq 1 ]
  rm -f "${WORK}/supervisord.log"
  crash_server 202
  run_cron
  [ "$(crash_count)" -eq 2 ]
}

@test "the record holds the size of supervisord.log, and a record from before that holds judges by the pid alone" {
  write_pin "${V1}"
  sv_log stopped
  run_cron
  read -r pid started seen build offset <"${WORK}/server-record"
  [ "${offset}" = "$(stat -c %s "${WORK}/supervisord.log")" ]
  echo "100 0 ${START} ${BUILD}" >"${WORK}/server-record"
  sv_log stopped
  crash_server 201
  run_cron
  [ "$(crash_count)" -eq 1 ]
}

@test "a stop in the log excuses a server that is back up or starting, not one that is down" {
  write_pin "${V1}"
  run_cron
  sv_log stopped
  set_state enshrouded-server STARTING
  advance 300
  run_cron
  [ "$(crash_count)" -eq 0 ]
  set_state enshrouded-server RUNNING 300
  advance 300
  run_cron
  sv_log stopped
  set_state enshrouded-server BACKOFF
  advance 300
  run_cron
  [ "$(crash_count)" -eq 1 ]
}

@test "a server that stops is no verdict at any state of the stop, and the next start is not a crash either" {
  write_pin "${V1}"
  run_cron
  set_state enshrouded-server STOPPING
  advance 300
  run_cron
  set_state enshrouded-server STOPPED
  advance 300
  run_cron
  set_state enshrouded-server RUNNING 777
  advance 300
  run_cron
  [ "$(crash_count)" -eq 0 ]
  [ "$(restarts)" -eq 0 ]
}

@test "a server that stopped by itself during the watch is no crash, but one that exited is" {
  after_restart 1 "120|enshrouded-server|RUNNING|777"
  log_at 190 stopped
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ ! -s "${STATE}/bad-list" ]
  [ "$(crash_count)" -eq 0 ]
  rm -rf "${WORK}/sv" "${STATE}" "${WORK}/restart-count" "${WORK}/after-restart-1" "${WORK}/server-record" "${WORK}/log-at"
  mkdir "${WORK}/sv"
  printf '0|RUNNING|100\n' >"${WORK}/sv/enshrouded-server"
  printf '0|EXITED|\n' >"${WORK}/sv/enshrouded-updater"
  install_by_hand "${V1}"
  advance 100000
  after_restart 1 "120|enshrouded-server|RUNNING|777"
  log_at 100190 exited
  run_cron
  [ "${status}" -eq 0 ]
  [ "$(crash_count)" -eq 1 ]
}

@test "a server that was stopped during the watch is no verdict, whatever else the log says" {
  log_start 70
  log_fault 150
  after_restart 1 "130|enshrouded-server|STOPPED|"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ ! -s "${STATE}/bad-list" ]
  [ "$(crash_count)" -eq 0 ]
}

@test "a server that does not come back after the restart and stays stopped is no verdict" {
  echo 1 >"${WORK}/restart-exit-1"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ "$(crash_count)" -eq 0 ]
}

@test "a server that is down at the first run of a container is a crash, and a second container in that state turns the map off" {
  write_pin "${V1}"
  set_state enshrouded-server FATAL
  run_cron
  [ "$(crash_count)" -eq 1 ]
  [[ "$(crash_line)" == *"count=1 decision=stays-on fault=none" ]]
  assert_installed "${V1}"
  advance 300
  run_cron
  [ "$(crash_count)" -eq 1 ]
  rm -f "${WORK}/fatal-marker" "${WORK}/server-record"
  advance 300
  run_cron
  [ "$(crash_count)" -eq 2 ]
  [[ "$(crash_line)" == *"count=2 decision=off"* ]]
  [ ! -e "${ROOT}/iphlpapi.dll" ]
  [ "$(<"${STATE}/bad-list")" = "${V1}" ]
}

@test "a server in BACKOFF at the first run of a container is a crash once, like FATAL" {
  write_pin "${V1}"
  set_state enshrouded-server BACKOFF
  run_cron
  [ "$(crash_count)" -eq 1 ]
  advance 300
  run_cron
  [ "$(crash_count)" -eq 1 ]
}

@test "a crash during the watch followed by a server that stays FATAL turns the map off at the next run" {
  after_restart 1 "120|enshrouded-server|FATAL|"
  run_cron
  [ "${status}" -eq 0 ]
  assert_installed "${V2}"
  [ "$(crash_count)" -eq 1 ]
  advance 300
  run_cron
  [ "$(crash_count)" -eq 2 ]
  [ ! -e "${ROOT}/iphlpapi.dll" ]
  [ "$(<"${STATE}/bad-list")" = "${V2}" ]
}

@test "a server that is down while the updater or a restart job runs is no crash and does not use up the container's one count" {
  write_pin "${V1}"
  set_state enshrouded-server FATAL
  set_state enshrouded-updater RUNNING 555
  run_cron
  [ "$(crash_count)" -eq 0 ]
  [ ! -e "${WORK}/fatal-marker" ]
  set_state enshrouded-updater EXITED
  advance 300
  run_cron
  [ "$(crash_count)" -eq 1 ]
}

@test "a server back in STARTING after it was up is a crash, unless something planned is running" {
  write_pin "${V1}"
  run_cron
  set_state enshrouded-server STARTING
  advance 300
  run_cron
  [ "$(crash_count)" -eq 1 ]
  rm -f "${WORK}/server-record" "${WORK}/fatal-marker"
  set_state enshrouded-server RUNNING 300
  advance 300
  run_cron
  set_state enshrouded-server STARTING
  set_state enshrouded-restart RUNNING 600
  advance 300
  run_cron
  [ "$(crash_count)" -eq 1 ]
}

@test "the crashed run is the last one that started by the time the server was last seen, though the new run has not logged its start yet" {
  write_pin "${V1}"
  log_start
  log_fault
  run_cron
  crash_server 201
  run_cron
  [[ "$(crash_line)" == *"decision=off fault=[livemap] FAULT code="* ]]
  [ ! -e "${ROOT}/iphlpapi.dll" ]
}

@test "a start line logged a few seconds after the server was last seen still belongs to the crashed run, one logged later does not" {
  write_pin "${V1}"
  log_start 5
  log_fault 100
  run_cron
  crash_server 201
  run_cron
  [[ "$(crash_line)" == *"decision=off fault=[livemap] FAULT code="* ]]
  rm -f "${STATE}/crashes" "${STATE}/bad-list" "${WORK}/server-record"
  install_by_hand "${V1}"
  echo "${START}" >"${WORK}/clock"
  printf '0|RUNNING|100\n' >"${WORK}/sv/enshrouded-server"
  : >"${ROOT}/livemap.log"
  log_start -600
  log_start 6
  log_fault 100
  run_cron
  crash_server 202
  run_cron
  [[ "$(crash_line)" == *"decision=stays-on fault=none" ]]
}

@test "a server, updater or restart job that changes state during the download stops the swap before the install" {
  local row
  for row in "enshrouded-updater|RUNNING|555" "enshrouded-restart|RUNNING|600" "enshrouded-force-update|STARTING|601" "enshrouded-reset-roles|STOPPING|602" "enshrouded-server|STOPPING|" "enshrouded-server|FATAL|"; do
    rm -rf "${WORK}/sv" "${WORK}/restart-count" "${WORK}/events"
    mkdir "${WORK}/sv"
    printf '0|RUNNING|100\n' >"${WORK}/sv/enshrouded-server"
    printf '0|EXITED|\n' >"${WORK}/sv/enshrouded-updater"
    echo "${row}" >"${WORK}/during-download"
    run_cron
    [ "${status}" -eq 0 ]
    assert_installed "${V1}"
    [ "$(restarts)" -eq 0 ]
    [ "$(events)" = "empty curl " ]
  done
}
