#!/bin/bash
set -euo pipefail

SOPS_CONFIG="/workspaces/spruyt-labs/.sops.yaml"

if [[ -f "$SOPS_AGE_KEY_FILE" ]]; then
  read -rp "Age key already exists at $SOPS_AGE_KEY_FILE. Overwrite? (y/N): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted: keeping existing age key."
    exit 0
  fi
  ./sops-decrypt.sh || true
  rm -f "$SOPS_AGE_KEY_FILE"
fi

age-keygen -o "$SOPS_AGE_KEY_FILE" 2>/tmp/agekey.pub || {
  echo "age-keygen failed"
  exit 1
}
chmod 400 "$SOPS_AGE_KEY_FILE"

AGE_PUBLIC_KEY=$(grep -i '^public key:' /tmp/agekey.pub | awk '{print $3}')
rm -f /tmp/agekey.pub

if [[ -n "$AGE_PUBLIC_KEY" ]]; then
  NEW_SOPS_CONFIG=$(awk -v newkey="$AGE_PUBLIC_KEY" '
    /^[[:space:]]*age1[0-9a-z]+[[:space:]]*$/ { sub(/age1[0-9a-z]+/, newkey); }
    { print }
  ' "$SOPS_CONFIG")
  printf "%s\n" "$NEW_SOPS_CONFIG" >"$SOPS_CONFIG"
  echo "✅ .sops.yaml updated with public key: $AGE_PUBLIC_KEY"
else
  echo "⚠️  Could not find the public key in age-keygen output. .sops.yaml not updated."
fi

echo "✅ New Age key created at $SOPS_AGE_KEY_FILE"

./sops-encrypt.sh || true
