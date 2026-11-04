#!/bin/bash
# Flux substitutes the braced form of a variable in rendered manifests: use plain $var only
# Exits 0 on every path: the image runs this before the server starts, so a map problem must not block it
# The pin file is the only source of the version and hash; --cron runs from the image's crontab, which has no container env, and never touches livemap.ini

mode=bootstrap
if [ "$1" = "--cron" ]; then
  mode=cron
fi

override() {
  local v
  v=$(printenv "$1")
  if [ -n "$v" ]; then
    echo "$v"
  else
    echo "$2"
  fi
}

root=$(override LIVEMAP_ROOT /opt/enshrouded/server)
pin_dir=$(override LIVEMAP_PIN_DIR /opt/livemap-pin)
state=$(override LIVEMAP_STATE_DIR /opt/enshrouded/livemap-state)
image_common=$(override LIVEMAP_IMAGE_COMMON /usr/local/etc/enshrouded/common)
updater_pidfile=$(override LIVEMAP_UPDATER_PIDFILE /var/run/enshrouded/enshrouded-updater.pid)
build_file=$(override LIVEMAP_BUILD_FILE /opt/enshrouded/current_version)
lock_file=$(override LIVEMAP_CRON_LOCK /tmp/livemap-cron.lock)
server_record=$(override LIVEMAP_SERVER_RECORD /tmp/livemap-server)
fatal_marker=$(override LIVEMAP_FATAL_MARKER /tmp/livemap-fatal)
supervisor_log=$(override LIVEMAP_SUPERVISOR_LOG /var/log/supervisor/supervisord.log)
ini=$root/livemap.ini
marker=$root/livemap/.installed
repo=anthony-spruyt/enshrouded-livemap

log() {
  if [ "$mode" = cron ]; then
    logger -t livemap-install -- "$*"
  else
    echo "livemap-install: $*"
  fi
}

pin_value() {
  sed -n "s/^$1: *\"\\([^\"]*\\)\".*/\\1/p" "$pin_dir/livemap-pin.yaml" 2>/dev/null | head -n 1
}

# Only a version shaped vX.Y.Z and a lowercase 64 digit hash from the pin file are used; the message never repeats the value
load_pin() {
  local LC_ALL=C
  pin_version=$(pin_value LIVEMAP_VERSION)
  pin_sha=$(pin_value LIVEMAP_SHA256)
  if [[ ! $pin_version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    if [ -n "$pin_version" ]; then
      log "the pinned version is not shaped vX.Y.Z, ignoring it"
    fi
    pin_version=
  fi
  if [[ ! $pin_sha =~ ^[0-9a-f]{64}$ ]]; then
    if [ -n "$pin_sha" ]; then
      log "the pinned hash is not 64 lowercase hex digits, ignoring it"
    fi
    pin_sha=
  fi
}

up_to_date() {
  [ -n "$pin_sha" ] &&
    [ -f "$root/iphlpapi.dll" ] &&
    [ -f "$root/livemap/index.html" ] &&
    grep -qxF "$pin_sha" "$marker" 2>/dev/null
}

build_id() {
  local b
  b=$(tr -dc '0-9' <"$build_file" 2>/dev/null | head -c 20)
  if [ -n "$b" ]; then
    echo "$b"
  else
    echo unknown
  fi
}

is_bad() {
  grep -qxF "$1" "$state/bad-list" 2>/dev/null
}

# The marker holds the hash and the version; a marker with only the hash is from the older installer
installed_version() {
  local v
  v=$(sed -n 2p "$marker" 2>/dev/null)
  if [ -z "$v" ] && [ -n "$pin_sha" ] && grep -qxF "$pin_sha" "$marker" 2>/dev/null; then
    v=$pin_version
  fi
  if [ -z "$v" ]; then
    v=unknown
  fi
  echo "$v"
}

fetch_release() {
  local ver rc
  ver=$(printf '%s' "$pin_version" | sed 's/^v//')
  curl -fsSL --proto '=https' --connect-timeout 10 --max-time 80 --retry 2 \
    -o "$1/release.zip" \
    "https://github.com/$repo/releases/download/$pin_version/EnshroudedLiveMap-$ver.zip" 2>/dev/null
  rc=$?
  if [ "$rc" -ne 0 ]; then
    log "download of $pin_version failed (curl exit $rc), keeping installed files"
    return 1
  fi
  if ! (cd "$1" && echo "$pin_sha  release.zip" | sha256sum -c --status); then
    log "sha256 mismatch for $pin_version, keeping installed files"
    return 1
  fi
}

unpack_release() {
  python3 -I -m zipfile -e "$1/release.zip" "$1/x"
}

install_files() {
  mkdir -p "$root/livemap" &&
    cp -f "$1/iphlpapi.dll" "$root/iphlpapi.dll.new" &&
    mv -f "$root/iphlpapi.dll.new" "$root/iphlpapi.dll" &&
    cp -R "$1/livemap/." "$root/livemap/" &&
    printf '%s\n%s\n' "$pin_sha" "$pin_version" >"$marker"
}

install_release() {
  local tmp
  if [ -z "$pin_version" ] || [ -z "$pin_sha" ]; then
    log "version or sha256 not set, keeping installed files"
    return
  fi
  tmp=$(mktemp -d) || {
    log "no temp dir, keeping installed files"
    return
  }
  if fetch_release "$tmp"; then
    if unpack_release "$tmp" && install_files "$tmp/x"; then
      log "installed $pin_version"
    else
      log "install of $pin_version failed, will retry on the next start"
    fi
  fi
  rm -rf "$tmp"
}

existing_key() {
  [ -f "$ini" ] || return 0
  tr -d '\r' <"$ini" | awk '
    /^[ \t]*\[/ { s = (tolower($0) ~ /^[ \t]*\[livemap\][ \t]*$/) }
    s && tolower($0) ~ /^[ \t]*key[ \t]*=/ {
      sub(/^[^=]*=[ \t]*/, "")
      sub(/[ \t]+$/, "")
      print
      exit
    }'
}

# Same rule as key_ok in upstream src/link.cpp
key_ok() {
  local LC_ALL=C lower
  [[ $1 =~ ^[A-Za-z0-9_-]{3,64}$ ]] || return 1
  lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case $lower in
  state | events | finds | icons | index | livemap) return 1 ;;
  esac
}

new_key() {
  LC_ALL=C tr -dc 'abcdefghjkmnpqrstuvwxyz23456789' </dev/urandom | head -c 16
}

write_ini() {
  local key
  if key_ok "$LIVEMAP_KEY"; then
    key=$LIVEMAP_KEY
  else
    if [ -n "$LIVEMAP_KEY" ]; then
      log "LIVEMAP_KEY is not a valid map key (3-64 letters, digits, - or _, not a reserved word), ignoring it"
    fi
    key=$(existing_key)
  fi
  if [ -z "$key" ]; then
    key=$(new_key)
  fi
  if [ -z "$key" ]; then
    log "no key available, leaving livemap.ini as it is"
    return
  fi
  if (
    umask 077
    cat >"$ini.new" <<EOF
[livemap]
Enabled=1
Port=15637
Bind=0.0.0.0
PublicUrl=$LIVEMAP_PUBLIC_URL
DetectPublicAddress=0
AnnounceInChat=1
UpdateMs=250
Log=1
LogDiagnostics=0
Key=$key
EOF
  ) && mv -f "$ini.new" "$ini"; then
    log "wrote livemap.ini"
  else
    log "could not write livemap.ini"
  fi
}

trim_log() {
  local maplog=$root/livemap.log size
  [ -f "$maplog" ] || return 0
  size=$(stat -c %s "$maplog" 2>/dev/null) || return 0
  if [ "$size" -gt 10485760 ]; then
    if tail -n 1000 "$maplog" >"$maplog.tmp" && mv -f "$maplog.tmp" "$maplog"; then
      log "trimmed livemap.log to its last 1000 lines"
    else
      rm -f "$maplog.tmp"
      log "could not trim livemap.log"
    fi
  fi
}

inline_icon() {
  python3 -I - "$@" <<'PY'
import base64
import sys

page, icon, out = sys.argv[1:]
with open(icon, "rb") as f:
    uri = base64.b64encode(f.read())
with open(page, "rb") as f:
    html = f.read()
old = b'<link rel="icon" href="data:,">'
new = b'<link rel="icon" type="image/png" href="data:image/png;base64,' + uri + b'">'
with open(out, "wb") as f:
    f.write(html.replace(old, new))
PY
}

# Upstream ships an empty icon because every request needs the key; an inline data URI needs no request
set_favicon() {
  local page=$root/livemap/index.html icon=$root/livemap/icons/altar.png tmp
  grep -qF '<link rel="icon" href="data:,">' "$page" 2>/dev/null || return 0
  if [ ! -f "$icon" ]; then
    log "altar.png not found, leaving the live map without a favicon"
    return 0
  fi
  tmp=$page.new
  if inline_icon "$page" "$icon" "$tmp" 2>/dev/null && mv -f "$tmp" "$page"; then
    log "added the favicon to the live map page"
  else
    rm -f "$tmp"
    log "could not add the favicon to the live map page"
  fi
}

# supervisord prints its times in the container TZ and cron gives its jobs no environment
tz_prefix() {
  case $TZ in
  '' | *[!A-Za-z0-9_+/:.-]*) ;;
  *) printf 'TZ=%s ' "$TZ" ;;
  esac
}

# The image rewrites the crontab on every start, before this hook runs
ensure_cron() {
  local current cron_line
  cron_line="2-59/5 * * * * $(tz_prefix)timeout 2400 bash /opt/livemap/livemap-install.sh --cron >/dev/null 2>&1"
  current=$(crontab -l 2>/dev/null)
  if printf '%s\n' "$current" | grep -qxF "$cron_line"; then
    return
  fi
  if {
    printf '%s\n' "$current" | grep -v -e '^$' -e 'livemap-install\.sh --cron'
    printf '%s\n' "$cron_line"
  } | crontab - 2>/dev/null; then
    log "added the live map cron line"
  else
    log "could not add the live map cron line"
  fi
}

bootstrap_main() {
  ensure_cron
  rm -f "$server_record"
  load_pin
  if is_bad "$pin_version"; then
    log "$pin_version is on the bad list, not installing it"
  elif up_to_date; then
    log "$pin_version already installed"
  else
    install_release
  fi
  set_favicon
  write_ini
  trim_log
}

# Only the DLL's own dated start and failure lines set the state, so event lines with player text never match
log_status() {
  local map_state version
  read -r map_state version < <(tr -d '\r' <"$root/livemap.log" 2>/dev/null | awk '
    $1 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ { next }
    $3 == "livemap" && $5 == "starting:" { s = "active"; v = $4 }
    /; no live map$/ { s = "inactive" }
    / disabled in livemap\.ini$/ { s = "disabled" }
    END { print (s == "" ? "inactive" : s), (v == "" ? "unknown" : v) }')
  if [ ! -f "$root/iphlpapi.dll" ]; then
    map_state=off
  fi
  logger -t livemap-status -- "state=$map_state version=$version build=$(build_id)"
}

# Prints "STATE pid start-epoch"; supervisorctl exits 3 for any program that is not RUNNING, so only its text counts
sv_status() {
  local st pid rest when
  read -r st pid rest < <(timeout 20 supervisorctl status "$1" 2>/dev/null | awk -v n="$1" '
    $1 != n { next }
    $2 != "RUNNING" { print $2, "-", substr($0, index($0, $3)); exit }
    {
      p = $4; sub(/,$/, "", p)
      u = $0; sub(/^.*uptime /, "", u)
      d = 0
      if (u ~ /days?, /) { d = u; sub(/ day.*$/, "", d); sub(/^.*days?, /, "", u) }
      split(u, t, ":")
      print "RUNNING", p, d * 86400 + t[1] * 3600 + t[2] * 60 + t[3]
      exit
    }')
  case $st in
  RUNNING) echo "$st $pid $(($(date +%s) - rest))" ;;
  EXITED)
    when=$(date -d "$rest $(date +%Y)" +%s 2>/dev/null)
    # supervisord leaves out the year: a time more than a day ahead is from last year
    if [ -n "$when" ] && [ "$when" -gt $(($(date +%s) + 86400)) ]; then
      when=$(date -d "$rest $(($(date +%Y) - 1))" +%s 2>/dev/null)
    fi
    echo "$st - $when"
    ;;
  '') ;;
  *) echo "$st - -" ;;
  esac
}

# Read-only: the image's checkLock signals whatever PID is in this file and stops while it is alive
updater_busy() {
  local pid st rest
  pid=$(head -n 1 "$updater_pidfile" 2>/dev/null)
  case $pid in
  '' | *[!0-9]*) ;;
  *) kill -0 "$pid" 2>/dev/null && return 0 ;;
  esac
  read -r st rest <<<"$(sv_status enshrouded-updater)"
  case $st in
  RUNNING | STARTING) return 0 ;;
  esac
  return 1
}

# The image's other planned stops of the server: RESTART_CRON, a forced update and a role reset
helpers='enshrouded-restart enshrouded-force-update enshrouded-reset-roles'

planned_busy() {
  local p st rest
  if updater_busy; then
    return 0
  fi
  for p in $helpers; do
    read -r st rest <<<"$(sv_status "$p")"
    case $st in
    RUNNING | STARTING | STOPPING) return 0 ;;
    esac
  done
  return 1
}

# EXITED times have minute resolution, hence the 60 s of slack
helper_ran_since() {
  local p st pid when
  for p in $helpers; do
    read -r st pid when <<<"$(sv_status "$p")"
    case $st in
    EXITED)
      if [ $((when + 60)) -gt "$1" ]; then
        return 0
      fi
      ;;
    esac
  done
  return 1
}

# A missing checkServerEmpty counts as not empty; it only works as the enshrouded user, which cron is
server_empty() {
  timeout 30 bash -c '. "$1" >/dev/null 2>&1; type checkServerEmpty >/dev/null 2>&1 && checkServerEmpty true' _ "$image_common" >/dev/null 2>&1
}

# Stopping takes about 66 s until mornedhels/enshrouded-server#265 is fixed: 180 s leaves room for stop and start
restart_server() {
  timeout 180 supervisorctl restart enshrouded-server >/dev/null 2>&1
}

log_size() {
  stat -c %s "$supervisor_log" 2>/dev/null || echo 0
}

# What supervisord logged for the server since byte $1: crash when it exited on its own, planned when it was only stopped
server_log_says() {
  case $1 in
  '' | *[!0-9]*)
    echo unknown
    return
    ;;
  esac
  tail -c +$(($1 + 1)) "$supervisor_log" 2>/dev/null | awk '
    $5 == "enshrouded-server" && $4 == "exited:" { crashed = 1 }
    $5 == "enshrouded-server" && $4 == "stopped:" { stopped = 1 }
    END { print crashed ? "crash" : stopped ? "planned" : "unknown" }'
}

# A server that is back up under a new pid, or starting, after only a stop in the log was restarted on purpose
log_excuses() {
  case $1 in
  RUNNING | STARTING) [ "$(server_log_says "$2")" = planned ] ;;
  *) return 1 ;;
  esac
}

# Sets run_pid and run_state
await_running() {
  local start st ignored
  start=$(date +%s)
  while :; do
    read -r st run_pid ignored <<<"$(sv_status enshrouded-server)"
    if [ "$st" = RUNNING ]; then
      return 0
    fi
    if [ $(($(date +%s) - start)) -ge 120 ]; then
      run_state=$st
      return 1
    fi
    sleep 10
  done
}

# Returns 0 when the server survives 10 min, 1 when it stops, 2 when a planned stop, the updater, a helper or a game update explains the stop; sets watch_from
watch_server() {
  local start st pid ignored offset failed=0
  if await_running; then
    start=$(date +%s)
    watch_from=$start
    offset=$(log_size)
    while [ $(($(date +%s) - start)) -lt 600 ]; do
      sleep 10
      read -r st pid ignored <<<"$(sv_status enshrouded-server)"
      if [ "$st" != RUNNING ] || [ "$pid" != "$run_pid" ]; then
        failed=1
        break
      fi
    done
  else
    watch_from=$(date +%s)
    st=$run_state
    failed=1
  fi
  if [ "$failed" = 0 ]; then
    return 0
  fi
  case $st in
  STOPPING | STOPPED) return 2 ;;
  esac
  if log_excuses "$st" "$offset"; then
    return 2
  fi
  if planned_busy || [ "$(build_id)" != "$1" ]; then
    return 2
  fi
  return 1
}

# Dated lines only, so player text in event lines never counts; the section is the run of the last DLL start line stamped within 5 s after $1 (the DLL stamps UTC)
fault_line() {
  local cutoff
  cutoff=$(date -u -d "@$(($1 + 5))" '+%Y-%m-%d %H:%M:%S')
  tr -d '\r' <"$root/livemap.log" 2>/dev/null | grep -v -i -E "announce|key=" | awk -v cutoff="$cutoff" '
    $1 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ { next }
    $3 == "livemap" && $5 == "starting:" {
      if ($1 " " substr($2, 1, 8) > cutoff) exit
      n++
      next
    }
    $3 == "[livemap]" && $4 == "FAULT" {
      line = $0
      sub(/^[^ ]+ [^ ]+ /, "", line)
      f[n] = line
    }
    END { print f[n] }' | tr -cd '[:print:]' | cut -c 1-200
}

new_dump() {
  find "$root/crash_dumps" -maxdepth 1 -type f -newermt "@$1" -printf '%f\n' 2>/dev/null | tail -n 1 | tr -cd 'A-Za-z0-9._-'
}

# Prints how many crashes of this version the last 24 h hold, this one included
count_crash() {
  local now keep
  now=$(date +%s)
  mkdir -p "$state"
  keep=$(awk -v n="$now" '$1 > n - 86400' "$state/crashes" 2>/dev/null)
  {
    if [ -n "$keep" ]; then
      echo "$keep"
    fi
    echo "$now $1"
  } >"$state/crashes.new" && mv -f "$state/crashes.new" "$state/crashes"
  awk -v v="$1" '$2 == v { c++ } END { print c + 0 }' "$state/crashes"
}

# The one rule for turning the map off: the DLL reports a fault, or this version crashed the server twice within 24 h
crash_decision() {
  if [ -n "$1" ] || [ "$2" -ge 2 ]; then
    echo off
  else
    echo stays-on
  fi
}

map_off() {
  mkdir -p "$state"
  if ! is_bad "$1"; then
    echo "$1" >>"$state/bad-list"
  fi
  rm -f "$root/iphlpapi.dll"
  log "the live map is off: $1 stays off until a newer version is pinned"
  if server_empty; then
    log "restarting the server to unload the live map"
    restart_server
  else
    log "players are on: the live map unloads at the next restart"
  fi
}

# $1 is when the server was last seen healthy
handle_crash() {
  local version dump fault count decision shown_dump=none shown_fault=none
  if [ ! -f "$root/iphlpapi.dll" ]; then
    return
  fi
  version=$(installed_version)
  dump=$(new_dump "$1")
  fault=$(fault_line "$1")
  count=$(count_crash "$version")
  decision=$(crash_decision "$fault" "$count")
  if [ -n "$dump" ]; then
    shown_dump=$dump
  fi
  if [ -n "$fault" ]; then
    shown_fault=$fault
  fi
  logger -t livemap-crash -- "version=$version build=$(build_id) dump=$shown_dump count=$count decision=$decision fault=$shown_fault"
  if [ "$decision" = off ]; then
    map_off "$version"
  fi
}

# Written as "pid start-epoch seen-epoch build log-size"; no record means the server was not RUNNING at the last run
record_server() {
  local st pid started
  read -r st pid started <<<"$(sv_status enshrouded-server)"
  if [ "$st" = RUNNING ]; then
    echo "$pid $started $(date +%s) $(build_id) $(log_size)" >"$server_record"
  else
    rm -f "$server_record"
  fi
}

# An unplanned stop is a new pid or start time, or a dead server, with no stop in the log, updater, helper or game update to explain it
# A server that is down with no record counts once per container (the marker), so a crash loop that restarts the container still adds up
check_server() {
  local st pid started rpid rstarted rseen rbuild roffset diff crashed=0
  read -r st pid started <<<"$(sv_status enshrouded-server)"
  if [ -f "$server_record" ]; then
    read -r rpid rstarted rseen rbuild roffset <"$server_record"
  fi
  case $st in
  RUNNING)
    diff=$((started - rstarted))
    if [ -n "$rpid" ] && { [ "$pid" != "$rpid" ] || [ "$diff" -gt 60 ] || [ "$diff" -lt -60 ]; }; then
      crashed=1
    fi
    ;;
  STARTING | EXITED)
    if [ -n "$rpid" ]; then
      crashed=1
    fi
    ;;
  BACKOFF | FATAL)
    if [ -n "$rpid" ] || [ ! -e "$fatal_marker" ]; then
      crashed=1
    fi
    ;;
  STOPPING | STOPPED) ;;
  *) return ;;
  esac
  if [ "$crashed" = 1 ]; then
    if log_excuses "$st" "$roffset" || planned_busy; then
      crashed=0
    elif [ -z "$rpid" ]; then
      rseen=$(date +%s)
    elif [ "$(build_id)" != "$rbuild" ] || helper_ran_since "$rseen"; then
      crashed=0
    fi
  fi
  if [ "$crashed" = 1 ]; then
    case $st in
    BACKOFF | FATAL) : >"$fatal_marker" ;;
    esac
    crash_handled=1
    handle_crash "$rseen"
  fi
  record_server
}

finish_swap() {
  watch_server "$1"
  case $? in
  0)
    log "$pin_version survived the watch on game build $1"
    ;;
  1)
    log "the server stopped on $pin_version with game build $1"
    handle_crash "$watch_from"
    ;;
  *)
    log "the updater or a game update ran during the watch of $pin_version, no verdict"
    ;;
  esac
  record_server
}

swap_staged() {
  local st rest
  read -r st rest <<<"$(sv_status enshrouded-server)"
  if [ "$st" != RUNNING ] || planned_busy; then
    log "not swapping to $pin_version: the server is not running or something planned started during the download"
    return
  fi
  if ! server_empty; then
    log "not swapping to $pin_version: players joined during the download"
    return
  fi
  if ! install_files "$1"; then
    log "install of $pin_version failed"
    return
  fi
  set_favicon
  log "swapping to $pin_version on game build $2"
  restart_server
  finish_swap "$2"
}

swap_release() {
  local tmp
  if ! server_empty; then
    log "not swapping to $pin_version: the server is not empty"
    return
  fi
  tmp=$(mktemp -d) || return
  if fetch_release "$tmp"; then
    if unpack_release "$tmp"; then
      swap_staged "$tmp/x" "$1"
    else
      log "could not unpack $pin_version, keeping installed files"
    fi
  fi
  rm -rf "$tmp"
}

cron_swap() {
  local st rest
  if [ -z "$pin_version" ] || [ -z "$pin_sha" ] || up_to_date || is_bad "$pin_version"; then
    return
  fi
  read -r st rest <<<"$(sv_status enshrouded-server)"
  if [ "$st" != RUNNING ] || planned_busy; then
    return
  fi
  swap_release "$(build_id)"
}

cron_main() {
  log_status
  (
    flock -n 9 || exit 0
    crash_handled=0
    load_pin
    check_server
    if [ "$crash_handled" = 0 ]; then
      cron_swap
    fi
  ) 9>"$lock_file"
}

if [ "$mode" = cron ]; then
  cron_main
else
  bootstrap_main
fi
exit 0
