#!/usr/bin/env bash
set -euo pipefail

# Runs Renovate in dry-run mode against local files.
#
# Problem: renovate.json5 uses github> self-referencing presets that resolve
# from the default branch via API, not local files. This script merges all
# local preset files into a temporary config so local changes can be tested.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RENOVATE_DIR="$REPO_ROOT/.github/renovate"
MAIN_CONFIG="$REPO_ROOT/.github/renovate.json5"
MERGED_CONFIG="$(mktemp)"

trap 'rm -f "$MERGED_CONFIG"' EXIT

# Resolve GitHub token
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if [[ -z "$TOKEN" ]] && command -v gh &>/dev/null; then
    TOKEN="$(gh auth token 2>/dev/null || true)"
fi
if [[ -z "$TOKEN" ]]; then
    echo "ERROR: No GitHub token found. Set GITHUB_TOKEN, GH_TOKEN, or authenticate with 'gh auth login'." >&2
    exit 1
fi

# Check renovate is installed
if ! command -v renovate &>/dev/null; then
    echo "ERROR: renovate CLI not found. Install with: npm install -g renovate" >&2
    exit 1
fi

# Check python3 + json5 are available
if ! python3 -c "import json5" 2>/dev/null; then
    echo "Installing json5 Python package..." >&2
    pip install -q json5
fi

# Merge all preset files into one config
python3 - "$MAIN_CONFIG" "$RENOVATE_DIR" "$MERGED_CONFIG" <<'PYEOF'
import json, json5, glob, sys, os

main_config, preset_dir, output = sys.argv[1], sys.argv[2], sys.argv[3]

with open(main_config) as f:
    config = json5.loads(f.read())

# Strip github> self-referencing presets, keep built-in presets
config['extends'] = [e for e in config.get('extends', []) if not e.startswith('github>')]

# Merge each preset file
for path in sorted(glob.glob(os.path.join(preset_dir, '*.json5'))):
    with open(path) as f:
        preset = json5.loads(f.read())
    for key, val in preset.items():
        if key in ('$schema', 'description'):
            continue
        if key in config and isinstance(config[key], list) and isinstance(val, list):
            config[key].extend(val)
        elif key in config and isinstance(config[key], dict) and isinstance(val, dict):
            config[key].update(val)
        else:
            config[key] = val

with open(output, 'w') as f:
    json.dump(config, f, indent=2)

print(f"Merged {len(glob.glob(os.path.join(preset_dir, '*.json5')))} preset files", file=sys.stderr)
PYEOF

echo "Running Renovate dry-run with merged local config..."
echo ""

# Temporarily swap config files
BACKUP="$MAIN_CONFIG.dryrun-backup"
cp "$MAIN_CONFIG" "$BACKUP"
cp "$MERGED_CONFIG" "$MAIN_CONFIG"

restore_config() {
    mv "$BACKUP" "$MAIN_CONFIG"
    rm -f "$MERGED_CONFIG"
}
trap restore_config EXIT

LOG_LEVEL="${LOG_LEVEL:-debug}" \
GITHUB_TOKEN="$TOKEN" \
renovate \
    --platform=local \
    --dry-run \
    "$@" 2>&1 | tee /tmp/renovate-dry-run.log

echo ""
echo "Full log saved to /tmp/renovate-dry-run.log"
