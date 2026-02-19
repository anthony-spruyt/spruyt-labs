#!/bin/sh
set -e
# Entrypoint wrapper: prepends custom paths to PATH
NPM_GLOBAL=/home/node/.openclaw/npm-global
export PATH="/home/node/.openclaw/bin:/home/node/.openclaw/go/bin:/home/node/.openclaw/python/bin:$NPM_GLOBAL/bin:$PATH"
export GOPATH="/home/node/.openclaw/gopath"
export GOROOT="/home/node/.openclaw/go"

# Set up Aikido safe-chain shims for runtime npm/npx/pip/uv protection
# HOME defaults to /home/node (read-only rootfs), so point safe-chain at /tmp
if [ -f "$NPM_GLOBAL/bin/safe-chain" ]; then
  SAFE_CHAIN_HOME=/tmp
  HOME="$SAFE_CHAIN_HOME" "$NPM_GLOBAL/bin/safe-chain" setup-ci 2>/dev/null || true
  export PATH="$SAFE_CHAIN_HOME/.safe-chain/shims:$SAFE_CHAIN_HOME/.safe-chain/bin:$PATH"
fi

exec "$@"
