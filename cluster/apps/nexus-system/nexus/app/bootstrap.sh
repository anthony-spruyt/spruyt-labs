#!/bin/sh
# cluster/apps/nexus-system/nexus/app/bootstrap.sh
#
# Bootstrap sidecar for Nexus: on first boot with a fresh PVC, Nexus writes
# a random password to /nexus-data/admin.password. This script waits for it,
# creates the desired admin user (NEXUS_USER/NEXUS_PASSWORD from secret) with
# nx-admin role, disables the built-in "admin" user, and leaves a marker so
# subsequent restarts no-op.
#
# NOTE: $${VAR} = envsubst-escaped so Flux leaves it literal ${VAR} for sh.
#
# shellcheck disable=SC2193,SC2195
set -eu

MARKER=/nexus-data/.bootstrap-done
if [ -f "$${MARKER}" ]; then
  echo "bootstrap already complete, idling"
  exec sleep infinity
fi

echo "waiting for /nexus-data/admin.password..."
for i in $(seq 1 120); do
  [ -f /nexus-data/admin.password ] && break
  sleep 5
done
if [ ! -f /nexus-data/admin.password ]; then
  echo "admin.password never appeared after 10min"
  exit 1
fi
BOOT_PW=$(cat /nexus-data/admin.password)

echo "waiting for nexus writable..."
for i in $(seq 1 120); do
  code=$(curl -sf -o /dev/null -w '%{http_code}' \
    http://localhost:8081/service/rest/v1/status/writable || true)
  [ "$${code}" = "200" ] && break
  sleep 5
done
[ "$${code}" = "200" ] || {
  echo "nexus never writable"
  exit 1
}

API="http://localhost:8081/service/rest/v1"
BOOT_AUTH="admin:$${BOOT_PW}"

echo "creating user $${NEXUS_USER}..."
body=$(printf '{"userId":"%s","firstName":"Admin","lastName":"User","emailAddress":"%s@local","password":"%s","status":"active","roles":["nx-admin"]}' \
  "$${NEXUS_USER}" "$${NEXUS_USER}" "$${NEXUS_PASSWORD}")
http=$(curl -sS -o /tmp/resp -w '%{http_code}' -u "$${BOOT_AUTH}" \
  -X POST -H "Content-Type: application/json" -d "$${body}" \
  "$${API}/security/users")
case "$${http}" in
2*)
  echo "  user created"
  ;;
400 | 409)
  if grep -qi "exist\|duplicate" /tmp/resp; then
    echo "  user exists, resetting password"
    curl -sfS -u "$${BOOT_AUTH}" -X PUT \
      -H "Content-Type: text/plain" \
      -d "$${NEXUS_PASSWORD}" \
      "$${API}/security/users/$${NEXUS_USER}/change-password"
  else
    echo "  user create failed HTTP $${http}: $(cat /tmp/resp)"
    exit 1
  fi
  ;;
*)
  echo "  user create failed HTTP $${http}: $(cat /tmp/resp)"
  exit 1
  ;;
esac

echo "disabling default admin user..."
curl -sfS -u "$${BOOT_AUTH}" -X PUT \
  -H "Content-Type: application/json" \
  -d '{"userId":"admin","firstName":"Administrator","lastName":"User","emailAddress":"admin@example.org","source":"default","status":"disabled","roles":["nx-admin"]}' \
  "$${API}/security/users/admin"

echo "removing bootstrap admin.password file..."
rm -f /nexus-data/admin.password

echo "writing marker..."
touch "$${MARKER}"

echo "bootstrap complete, idling"
exec sleep infinity
