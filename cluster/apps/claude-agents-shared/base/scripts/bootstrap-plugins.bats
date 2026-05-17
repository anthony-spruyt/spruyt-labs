#!/usr/bin/env bats

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME/.claude"
  mkdir -p "$TEST_DIR/repo/.claude"
  mkdir -p "$TEST_DIR/managed"
  mkdir -p "$TEST_DIR/bin"

  # Copy script and replace hardcoded paths with test paths
  SCRIPT="$TEST_DIR/bootstrap-plugins.sh"
  cp "$BATS_TEST_DIRNAME/bootstrap-plugins.sh" "$SCRIPT"
  sed -i "s|REPO_DIR=\"/workspace/repo\"|REPO_DIR=\"$TEST_DIR/repo\"|" "$SCRIPT"
  sed -i "s|/etc/claude-code/managed-settings.json|$TEST_DIR/managed/managed-settings.json|" "$SCRIPT"
  chmod +x "$SCRIPT"

  # Mock claude CLI — logs calls to file
  cat >"$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
echo "\$@" >> "${TEST_DIR}/claude-calls.log"
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  # Put mock claude (and real jq) on PATH
  if command -v jq >/dev/null 2>&1; then
    ln -s "$(command -v jq)" "$TEST_DIR/bin/jq"
  fi
  export PATH="$TEST_DIR/bin:$PATH"
  export TEST_DIR
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "missing settings file: skip gracefully, exit 0" {
  # No settings files created — all paths missing
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[plugin-bootstrap] done"* ]]
}

@test "empty JSON object: no installs, exit 0" {
  echo '{}' >"$TEST_DIR/managed/managed-settings.json"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[plugin-bootstrap] reading"* ]]
  [[ "$output" == *"[plugin-bootstrap] done"* ]]
  # No claude calls should have been made
  [ ! -f "$TEST_DIR/claude-calls.log" ]
}

@test "invalid JSON: exit 1" {
  echo '{bad json' >"$TEST_DIR/managed/managed-settings.json"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid JSON"* ]]
}

@test "disabled plugins (false): not installed" {
  cat >"$TEST_DIR/managed/managed-settings.json" <<'JSON'
{"enabledPlugins": {"foo": false, "bar": false}}
JSON
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  # No claude calls — disabled plugins are filtered out
  [ ! -f "$TEST_DIR/claude-calls.log" ]
}

@test "string true handling: plugin installed" {
  cat >"$TEST_DIR/managed/managed-settings.json" <<'JSON'
{"enabledPlugins": {"my-plugin": "true"}}
JSON
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[plugin-bootstrap] install: my-plugin"* ]]
  grep -q "plugins install my-plugin --scope user" "$TEST_DIR/claude-calls.log"
}

@test "missing jq command: exit 1" {
  # Remove jq from the test bin so the restricted PATH has neither jq nor claude
  rm -f "$TEST_DIR/bin/jq"
  local bash_path
  bash_path="$(command -v bash)"
  run env -i HOME="$HOME" TEST_DIR="$TEST_DIR" PATH="$TEST_DIR/bin" "$bash_path" "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq not found"* ]]
}

@test "missing claude command: exit 1" {
  # Run with a PATH that has jq but no claude
  local restricted_bin bash_path
  restricted_bin="$(mktemp -d)"
  bash_path="$(command -v bash)"
  ln -s "$(command -v jq)" "$restricted_bin/jq"
  run env -i HOME="$HOME" TEST_DIR="$TEST_DIR" PATH="$restricted_bin" "$bash_path" "$SCRIPT"
  rm -rf "$restricted_bin"
  [ "$status" -eq 1 ]
  [[ "$output" == *"claude CLI not found"* ]]
}

@test "marketplace + plugin install: both called" {
  cat >"$TEST_DIR/managed/managed-settings.json" <<'JSON'
{
  "extraKnownMarketplaces": {
    "my-market": {
      "source": {
        "repo": "owner/marketplace-repo"
      }
    }
  },
  "enabledPlugins": {
    "my-plugin": true
  }
}
JSON
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[plugin-bootstrap] marketplace add: my-market (owner/marketplace-repo)"* ]]
  [[ "$output" == *"[plugin-bootstrap] install: my-plugin"* ]]
  grep -q "plugins marketplace add owner/marketplace-repo --scope user" "$TEST_DIR/claude-calls.log"
  grep -q "plugins install my-plugin --scope user" "$TEST_DIR/claude-calls.log"
}

@test "marketplace with null repo: skipped" {
  cat >"$TEST_DIR/managed/managed-settings.json" <<'JSON'
{"extraKnownMarketplaces": {"m": {"source": {}}}}
JSON
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  # No marketplace add calls
  if [ -f "$TEST_DIR/claude-calls.log" ]; then
    ! grep -q "marketplace" "$TEST_DIR/claude-calls.log"
  fi
}
