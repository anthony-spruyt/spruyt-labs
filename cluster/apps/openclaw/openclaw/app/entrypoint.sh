#!/bin/sh
set -e
# Entrypoint wrapper: prepends custom paths to PATH
export PATH="/home/node/.openclaw/bin:/home/node/.openclaw/go/bin:/home/node/.openclaw/python/bin:$PATH"
export GOPATH="/home/node/.openclaw/gopath"
export GOROOT="/home/node/.openclaw/go"
exec "$@"
