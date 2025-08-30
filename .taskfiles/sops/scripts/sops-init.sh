#!/bin/bash
set -euo pipefail

AGE_KEY_PATH="/workspaces/spruyt-labs/secrets/age.key"
SOPS_CONFIG="/workspaces/spruyt-labs/.sops.yaml"

if [[ -f "$AGE_KEY_PATH" ]]; then
  read -p "Age key already exists at $AGE_KEY_PATH. Overwrite? (y/N): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted: keeping existing age key."
    exit 0
  fi
  ./sops-decrypt.sh || true
  rm -f "$AGE_KEY_PATH"
fi

age-keygen -o "$AGE_KEY_PATH" 2> /tmp/agekey.pub || { echo "age-keygen failed"; exit 1; }
chmod 400 "$AGE_KEY_PATH"

AGE_PUBLIC_KEY=$(grep -i '^public key:' /tmp/agekey.pub | awk '{print $3}')
rm -f /tmp/agekey.pub

if [[ -n "$AGE_PUBLIC_KEY" ]]; then
  NEW_SOPS_CONFIG=$(awk -v newkey="$AGE_PUBLIC_KEY" '
    /^[[:space:]]*age1[0-9a-z]+[[:space:]]*$/ { sub(/age1[0-9a-z]+/, newkey); }
    { print }
  ' "$SOPS_CONFIG")
  printf "%s\n" "$NEW_SOPS_CONFIG" > "$SOPS_CONFIG"
  echo "✅ .sops.yaml updated with public key: $AGE_PUBLIC_KEY"
else
  echo "⚠️  Could not find the public key in age-keygen output. .sops.yaml not updated."
fi

echo "✅ New Age key created at $AGE_KEY_PATH"

./sops-encrypt.sh || true
