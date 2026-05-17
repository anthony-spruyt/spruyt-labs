#!/usr/bin/env bats

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME/.claude"
  mkdir -p "$TEST_DIR/repo/.claude"
  mkdir -p "$TEST_DIR/managed"
  mkdir -p "$TEST_DIR/bin"

  SCRIPT="$BATS_TEST_DIRNAME/bootstrap-plugins.sh"
  MANAGED="$TEST_DIR/managed/managed-settings.json"
  PROJECT="$TEST_DIR/repo/.claude/settings.json"
  LOCAL="$TEST_DIR/repo/.claude/settings.local.json"

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

@test "no args: exit 0 immediately" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[plugin-bootstrap] done"* ]]
}

@test "missing settings file: skip gracefully, exit 0" {
  run bash "$SCRIPT" "$MANAGED" "$PROJECT" "$LOCAL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[plugin-bootstrap] done"* ]]
}

@test "empty JSON object: no installs, exit 0" {
  echo '{}' >"$MANAGED"
  run bash "$SCRIPT" "$MANAGED"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[plugin-bootstrap] reading"* ]]
  [[ "$output" == *"[plugin-bootstrap] done"* ]]
  [ ! -f "$TEST_DIR/claude-calls.log" ]
}

@test "invalid JSON: exit 1" {
  echo '{bad json' >"$MANAGED"
  run bash "$SCRIPT" "$MANAGED"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid JSON"* ]]
}

@test "disabled plugins (false): not installed" {
  cat >"$MANAGED" <<'JSON'
{"enabledPlugins": {"foo": false, "bar": false}}
JSON
  run bash "$SCRIPT" "$MANAGED"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DIR/claude-calls.log" ]
}

@test "string true handling: plugin installed" {
  cat >"$MANAGED" <<'JSON'
{"enabledPlugins": {"my-plugin": "true"}}
JSON
  run bash "$SCRIPT" "$MANAGED"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[plugin-bootstrap] install: my-plugin"* ]]
  grep -q "plugins install my-plugin --scope user" "$TEST_DIR/claude-calls.log"
}

@test "missing jq command: exit 1" {
  rm -f "$TEST_DIR/bin/jq"
  local bash_path
  bash_path="$(command -v bash)"
  run env -i HOME="$HOME" TEST_DIR="$TEST_DIR" PATH="$TEST_DIR/bin" "$bash_path" "$SCRIPT" "$MANAGED"
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq not found"* ]]
}

@test "missing claude command: exit 1" {
  local restricted_bin bash_path
  restricted_bin="$(mktemp -d "$TEST_DIR/restricted-bin-XXXX")"
  bash_path="$(command -v bash)"
  ln -s "$(command -v jq)" "$restricted_bin/jq"
  run env -i HOME="$HOME" TEST_DIR="$TEST_DIR" PATH="$restricted_bin" "$bash_path" "$SCRIPT" "$MANAGED"
  rm -rf "$restricted_bin"
  [ "$status" -eq 1 ]
  [[ "$output" == *"claude CLI not found"* ]]
}

@test "marketplace + plugin install: both called" {
  cat >"$MANAGED" <<'JSON'
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
  run bash "$SCRIPT" "$MANAGED"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[plugin-bootstrap] marketplace add: my-market (owner/marketplace-repo)"* ]]
  [[ "$output" == *"[plugin-bootstrap] install: my-plugin"* ]]
  grep -q "plugins marketplace add owner/marketplace-repo --scope user" "$TEST_DIR/claude-calls.log"
  grep -q "plugins install my-plugin --scope user" "$TEST_DIR/claude-calls.log"
}

@test "marketplace with null repo: skipped" {
  cat >"$MANAGED" <<'JSON'
{"extraKnownMarketplaces": {"m": {"source": {}}}}
JSON
  run bash "$SCRIPT" "$MANAGED"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DIR/claude-calls.log" ]
}

@test "multiple files: reads all in order" {
  cat >"$MANAGED" <<'JSON'
{"enabledPlugins": {"managed-plugin": true}}
JSON
  cat >"$PROJECT" <<'JSON'
{"enabledPlugins": {"project-plugin": true}}
JSON
  run bash "$SCRIPT" "$MANAGED" "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[plugin-bootstrap] install: managed-plugin"* ]]
  [[ "$output" == *"[plugin-bootstrap] install: project-plugin"* ]]
  grep -q "plugins install managed-plugin --scope user" "$TEST_DIR/claude-calls.log"
  grep -q "plugins install project-plugin --scope user" "$TEST_DIR/claude-calls.log"
}
