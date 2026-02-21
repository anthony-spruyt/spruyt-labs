#!/bin/sh
# Init container: config merge/overwrite
# Merges Helm-managed config (/config/openclaw.json) with existing PVC config,
# or overwrites if CONFIG_MODE=overwrite or no existing config exists.
set -e

log() { echo "[$(date -Iseconds)] [init-config] $*"; }

log "Starting config initialization"
mkdir -p /home/node/.openclaw
CONFIG_MODE="$${CONFIG_MODE:-merge}"

if [ "$CONFIG_MODE" = "merge" ] && [ -f /home/node/.openclaw/openclaw.json ]; then
  log "Mode: merge - merging Helm config with existing config"
  if node -e "
    const fs = require('fs');
    // Strip JSON5 single-line comments while preserving // inside strings (e.g. URLs)
    const stripComments = (s) => {
      let r = '', q = false, i = 0;
      while (i < s.length) {
        if (q) {
          if (s[i] === '\\\\') { r += s[i] + s[i+1]; i += 2; continue; }
          if (s[i] === '\"') q = false;
          r += s[i++];
        } else if (s[i] === '\"') {
          q = true; r += s[i++];
        } else if (s[i] === '/' && s[i+1] === '/') {
          while (i < s.length && s[i] !== '\n') i++;
        } else { r += s[i++]; }
      }
      return r;
    };
    let existing;
    try {
      existing = JSON.parse(stripComments(fs.readFileSync('/home/node/.openclaw/openclaw.json', 'utf8')));
    } catch (e) {
      console.error('[init-config] Warning: existing config is not valid JSON, will overwrite');
      process.exit(1);
    }
    const helm = JSON.parse(stripComments(fs.readFileSync('/config/openclaw.json', 'utf8')));
    const deepMerge = (target, source) => {
      for (const key of Object.keys(source)) {
        if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key])) {
          target[key] = target[key] || {};
          deepMerge(target[key], source[key]);
        } else {
          target[key] = source[key];
        }
      }
      return target;
    };
    const merged = deepMerge(existing, helm);
    fs.writeFileSync('/home/node/.openclaw/openclaw.json', JSON.stringify(merged, null, 2));
  "; then
    log "Config merged successfully"
  else
    log "WARNING: Merge failed (existing config may not be valid JSON), falling back to overwrite"
    cp /config/openclaw.json /home/node/.openclaw/openclaw.json
  fi
else
  if [ ! -f /home/node/.openclaw/openclaw.json ]; then
    log "Fresh install - writing initial config"
  else
    log "Mode: overwrite - replacing config with Helm values"
  fi
  cp /config/openclaw.json /home/node/.openclaw/openclaw.json
fi
log "Config initialization complete"
