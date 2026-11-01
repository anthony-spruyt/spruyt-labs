#!/bin/bash
# Flux substitutes the braced form of a variable in rendered manifests: use plain $var only
# Exits 0 on every path: the image runs this before the server starts, so a map problem must not block it

root=/opt/enshrouded/server
if [ -n "$LIVEMAP_ROOT" ]; then
  root=$LIVEMAP_ROOT
fi
ini=$root/livemap.ini
marker=$root/livemap/.installed

log() {
  echo "livemap-install: $*"
}

up_to_date() {
  [ -n "$LIVEMAP_SHA256" ] &&
    [ -f "$root/iphlpapi.dll" ] &&
    [ -f "$root/livemap/index.html" ] &&
    grep -qxF "$LIVEMAP_SHA256" "$marker" 2>/dev/null
}

install_release() {
  local tmp ver rc
  if [ -z "$LIVEMAP_VERSION" ] || [ -z "$LIVEMAP_SHA256" ]; then
    log "version or sha256 not set, keeping installed files"
    return
  fi
  tmp=$(mktemp -d) || {
    log "no temp dir, keeping installed files"
    return
  }
  ver=$(printf '%s' "$LIVEMAP_VERSION" | sed 's/^v//')
  curl -fsSL --proto '=https' --connect-timeout 10 --max-time 80 --retry 2 \
    -o "$tmp/release.zip" \
    "https://github.com/oggii/enshrouded-livemap/releases/download/$LIVEMAP_VERSION/EnshroudedLiveMap-$ver.zip" 2>/dev/null
  rc=$?
  if [ "$rc" -ne 0 ]; then
    log "download of $LIVEMAP_VERSION failed (curl exit $rc), keeping installed files"
  elif ! (cd "$tmp" && echo "$LIVEMAP_SHA256  release.zip" | sha256sum -c --status); then
    log "sha256 mismatch for $LIVEMAP_VERSION, keeping installed files"
  elif ! python3 -I -m zipfile -e "$tmp/release.zip" "$tmp/x" ||
    ! mkdir -p "$root/livemap" ||
    ! cp -f "$tmp/x/iphlpapi.dll" "$root/iphlpapi.dll.new" ||
    ! mv -f "$root/iphlpapi.dll.new" "$root/iphlpapi.dll" ||
    ! cp -R "$tmp/x/livemap/." "$root/livemap/" ||
    ! echo "$LIVEMAP_SHA256" >"$marker"; then
    log "install of $LIVEMAP_VERSION failed, will retry on the next start"
  else
    log "installed $LIVEMAP_VERSION"
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

if up_to_date; then
  log "$LIVEMAP_VERSION already installed"
else
  install_release
fi
set_favicon
write_ini
trim_log
exit 0
