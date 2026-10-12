#!/usr/bin/env bats
#
# builder-progress.sh tells a builder where its notes are on its first tool call and after each compaction.

bats_require_minimum_version 1.5.0

REPO_ROOT="${BATS_TEST_DIRNAME}/.."
SCRIPT="${REPO_ROOT}/.claude/scripts/builder-progress.sh"
AGENT=a1b2c3d4e5

setup() {
  TMP="$(mktemp -d)"
  export CLAUDE_PROJECT_DIR="${TMP}/project"
  mkdir -p "${CLAUDE_PROJECT_DIR}/.agent-progress" "${TMP}/claude/sess1/subagents"
  SESSION_FILE="${TMP}/claude/sess1.jsonl"
  TRANSCRIPT="${TMP}/claude/sess1/subagents/agent-${AGENT}.jsonl"
  : >"${SESSION_FILE}"
  : >"${TRANSCRIPT}"
  NOTES="${CLAUDE_PROJECT_DIR}/.agent-progress/builder-${AGENT}.md"
}

teardown() {
  rm -rf "${TMP}"
}

input() {
  jq -n --arg a "$1" --arg t "${2:-${SESSION_FILE}}" \
    '{session_id: "sess1", transcript_path: $t, agent_id: $a, hook_event_name: "PreToolUse", tool_name: "Bash"}'
}

hook() {
  run --separate-stderr bash "${SCRIPT}" <<<"$(input "$@")"
}

compact() {
  printf '%s\n' '{"type":"system","subtype":"compact_boundary","content":"Conversation compacted"}' >>"${TRANSCRIPT}"
}

context() {
  jq -r '.hookSpecificOutput.additionalContext' <<<"${output}"
}

@test "first call injects the notes path as PreToolUse additionalContext" {
  hook "${AGENT}"
  [ "${status}" -eq 0 ]
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"${output}")" = "PreToolUse" ]
  [[ "$(context)" == *"${NOTES}"* ]]
}

@test "second call is silent" {
  hook "${AGENT}"
  hook "${AGENT}"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "a new compact_boundary makes the next call inject again, once" {
  hook "${AGENT}"
  compact
  hook "${AGENT}"
  [ "${status}" -eq 0 ]
  [[ "$(context)" == *"${NOTES}"* ]]
  hook "${AGENT}"
  [ -z "${output}" ]
  compact
  hook "${AGENT}"
  [[ "$(context)" == *"${NOTES}"* ]]
}

@test "text that merely mentions compact_boundary is not a compaction" {
  hook "${AGENT}"
  printf '%s\n' '{"type":"user","message":{"content":"grep \"subtype\":\"compact_boundary\" file"}}' >>"${TRANSCRIPT}"
  hook "${AGENT}"
  [ -z "${output}" ]
}

@test "after a compaction the notes content is included" {
  hook "${AGENT}"
  printf 'GOAL: ship the thing\nNEXT: run tests\n' >"${NOTES}"
  compact
  hook "${AGENT}"
  [[ "$(context)" == *"GOAL: ship the thing"* ]]
  [[ "$(context)" == *"NEXT: run tests"* ]]
}

@test "notes are cut at 9000 characters and the cut is flagged" {
  hook "${AGENT}"
  head -c 12000 /dev/zero | tr '\0' 'n' >"${NOTES}"
  compact
  hook "${AGENT}"
  [ "${#output}" -lt 10000 ]
  [[ "$(context)" == *"truncated"* ]]
}

@test "the first call does not include notes" {
  printf 'OLD NOTES\n' >"${NOTES}"
  hook "${AGENT}"
  [[ "$(context)" != *"OLD NOTES"* ]]
}

@test "a transcript_path that is already the subagent file works" {
  hook "${AGENT}" "${TRANSCRIPT}"
  compact
  hook "${AGENT}" "${TRANSCRIPT}"
  [[ "$(context)" == *"${NOTES}"* ]]
}

@test "a missing transcript still injects on the first call and stays silent after" {
  rm "${TRANSCRIPT}"
  hook "${AGENT}"
  [[ "$(context)" == *"${NOTES}"* ]]
  hook "${AGENT}"
  [ -z "${output}" ]
}

@test "agents keep separate state" {
  hook "${AGENT}"
  hook other-agent
  [[ "$(context)" == *"builder-other-agent.md"* ]]
}

@test "an agent_id that is not a plain identifier is silent and writes nothing" {
  for bad in "../x" "a/b" "a b" 'a$b' "a.b" ""; do
    hook "${bad}"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
  done
  [ -z "$(ls -A "${CLAUDE_PROJECT_DIR}/.agent-progress")" ]
}

@test "no agent_id in the input is silent" {
  run --separate-stderr bash "${SCRIPT}" <<<'{"session_id":"sess1"}'
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "empty or malformed stdin is silent" {
  run --separate-stderr bash "${SCRIPT}" <<<''
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  run --separate-stderr bash "${SCRIPT}" <<<'not json'
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "without CLAUDE_PROJECT_DIR it is silent" {
  unset CLAUDE_PROJECT_DIR
  hook "${AGENT}"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "a symlinked notes file is silent and not followed" {
  printf 'SECRET\n' >"${TMP}/target.md"
  ln -s "${TMP}/target.md" "${NOTES}"
  hook "${AGENT}"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "a symlinked state file is silent and not written through" {
  printf 'x\n' >"${TMP}/target.state"
  ln -s "${TMP}/target.state" "${CLAUDE_PROJECT_DIR}/.agent-progress/builder-${AGENT}.state"
  hook "${AGENT}"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "$(cat "${TMP}/target.state")" = "x" ]
}

@test "a symlinked .agent-progress folder is silent" {
  rm -rf "${CLAUDE_PROJECT_DIR}/.agent-progress"
  mkdir "${TMP}/elsewhere"
  ln -s "${TMP}/elsewhere" "${CLAUDE_PROJECT_DIR}/.agent-progress"
  hook "${AGENT}"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "$(ls -A "${TMP}/elsewhere")" ]
}

@test "creates the notes folder when it is missing" {
  rmdir "${CLAUDE_PROJECT_DIR}/.agent-progress"
  hook "${AGENT}"
  [[ "$(context)" == *"${NOTES}"* ]]
}

@test "parallel calls after one compaction inject exactly once" {
  hook "${AGENT}"
  printf 'GOAL: ship the thing\n' >"${NOTES}"
  compact
  payload="$(input "${AGENT}")"
  for i in 1 2 3 4 5 6; do
    bash "${SCRIPT}" <<<"${payload}" >"${TMP}/out.${i}" &
  done
  wait
  [ "$(cat "${TMP}"/out.* | grep -c additionalContext)" -eq 1 ]
}

@test "parallel first calls inject exactly once" {
  payload="$(input "${AGENT}")"
  for i in 1 2 3 4 5 6; do
    bash "${SCRIPT}" <<<"${payload}" >"${TMP}/out.${i}" &
  done
  wait
  [ "$(cat "${TMP}"/out.* | grep -c additionalContext)" -eq 1 ]
}
