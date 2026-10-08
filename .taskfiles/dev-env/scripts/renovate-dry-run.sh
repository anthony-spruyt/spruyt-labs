#!/usr/bin/env bash
set -euo pipefail

# Renovate resolves github> presets from the remote default branch, so inline
# them with the local overrides to dry-run against the working tree.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
MAIN_CONFIG="$REPO_ROOT/renovate.json"
MERGED_CONFIG="$(mktemp)"
PRESET_TMPDIR="$(mktemp -d)"

trap 'rm -f "$MERGED_CONFIG"; rm -rf "$PRESET_TMPDIR"' EXIT

TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if [[ -z "$TOKEN" ]] && command -v gh &>/dev/null; then
  TOKEN="$(gh auth token 2>/dev/null || true)"
fi
if [[ -z "$TOKEN" ]]; then
  echo "ERROR: No GitHub token found. Set GITHUB_TOKEN, GH_TOKEN, or authenticate with 'gh auth login'." >&2
  exit 1
fi

if ! command -v renovate &>/dev/null; then
  echo "ERROR: renovate CLI not found. Install with: npm install -g renovate" >&2
  exit 1
fi

if ! python3 -c "import json5" 2>/dev/null; then
  echo "Installing json5 Python package..." >&2
  pip install -q json5
fi

python3 - "$MAIN_CONFIG" "$MERGED_CONFIG" "$PRESET_TMPDIR" "$TOKEN" "$REPO_ROOT" <<'PYEOF'
import json, json5, sys, os, urllib.request, base64

main_config, output, tmpdir, token, repo_root = sys.argv[1:6]

with open(main_config) as f:
    config = json5.loads(f.read())

github_presets = [e for e in config.get('extends', []) if e.startswith('github>')]
local_presets = [e for e in config.get('extends', []) if e.startswith('local>')]
config['extends'] = [e for e in config.get('extends', []) if not e.startswith(('github>', 'local>'))]

def fetch_github_preset(preset_ref, token):
    """Fetch a github>owner/repo//.path preset file via GitHub API."""
    ref = preset_ref.removeprefix('github>')
    if '//' in ref:
        repo_part, path_part = ref.split('//', 1)
    else:
        return None
    url = f"https://api.github.com/repos/{repo_part}/contents/{path_part}"
    req = urllib.request.Request(url, headers={
        'Authorization': f'token {token}',
        'Accept': 'application/vnd.github.v3+json',
    })
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())
            content = base64.b64decode(data['content']).decode('utf-8')
            return json5.loads(content)
    except Exception as e:
        print(f"  WARNING: Failed to fetch {preset_ref}: {e}", file=sys.stderr)
        return None

def merge_preset(config, preset):
    """Merge a preset dict into the config, extending lists and updating dicts."""
    for key, val in preset.items():
        if key in ('$schema', 'description'):
            continue
        if key in config and isinstance(config[key], list) and isinstance(val, list):
            config[key].extend(val)
        elif key in config and isinstance(config[key], dict) and isinstance(val, dict):
            config[key].update(val)
        else:
            config[key] = val

fetched = 0
for preset_ref in github_presets:
    print(f"  Fetching {preset_ref}...", file=sys.stderr)
    preset = fetch_github_preset(preset_ref, token)
    if preset:
        # Nested extends are dropped, not followed
        preset.pop('extends', None)
        merge_preset(config, preset)
        fetched += 1

local_count = 0
for local_ref in local_presets:
    raw_path = local_ref.removeprefix('local>')
    rel_path = raw_path.split('//', 1)[1] if '//' in raw_path else raw_path
    for ext in ['.json5', '.json', '']:
        candidate = os.path.join(repo_root, rel_path + ext)
        if os.path.isfile(candidate):
            print(f"  Merging local preset {candidate}...", file=sys.stderr)
            with open(candidate) as f:
                preset = json5.loads(f.read())
            merge_preset(config, preset)
            local_count += 1
            break

with open(output, 'w') as f:
    json.dump(config, f, indent=2)

print(f"Fetched {fetched} remote presets, merged {local_count} local overrides", file=sys.stderr)
PYEOF

echo "Running Renovate dry-run with merged local config..."
echo ""

# The local platform reads renovate.json from disk, so swap in the merged config
BACKUP="$MAIN_CONFIG.dryrun-backup"
cp "$MAIN_CONFIG" "$BACKUP"
cp "$MERGED_CONFIG" "$MAIN_CONFIG"

restore_config() {
  mv "$BACKUP" "$MAIN_CONFIG"
  rm -f "$MERGED_CONFIG"
  rm -rf "$PRESET_TMPDIR"
}
trap restore_config EXIT

LOG_LEVEL="${LOG_LEVEL:-debug}" \
  GITHUB_TOKEN="$TOKEN" \
  renovate \
  --platform=local \
  --dry-run=full \
  "$@" 2>&1 | tee /tmp/renovate-dry-run.log

echo ""
echo "Full log saved to /tmp/renovate-dry-run.log"
