#!/usr/bin/env bats
#
# builder-progress.sh tells a builder where its notes are on its first tool call and after each compaction,
# and in stop mode removes that builder's state and claim files.

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

stop_hook() {
  run --separate-stderr bash "${SCRIPT}" stop <<<"$(jq -n --arg a "$1" --arg t "${SESSION_FILE}" \
    '{session_id: "sess1", transcript_path: $t, agent_id: $a, hook_event_name: "SubagentStop"}')"
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

@test "the first call includes existing notes and does not say none are written" {
  printf 'OLD NOTES\n' >"${NOTES}"
  hook "${AGENT}"
  [[ "$(context)" == *"${NOTES}"* ]]
  [[ "$(context)" == *"OLD NOTES"* ]]
  [[ "$(context)" != *"none written yet"* ]]
  [[ "$(context)" != *"Write it now"* ]]
}

@test "the first call cuts long existing notes at 9000 characters and flags the cut" {
  head -c 12000 /dev/zero | tr '\0' 'n' >"${NOTES}"
  hook "${AGENT}"
  [ "${#output}" -lt 10000 ]
  [[ "$(context)" == *"truncated"* ]]
}

@test "the first call with an empty notes file asks for them" {
  : >"${NOTES}"
  hook "${AGENT}"
  [[ "$(context)" == *"none written yet"* ]]
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

@test "the first-call text makes notes required, not optional" {
  hook "${AGENT}"
  [[ "$(context)" != *"multi-step"* ]]
  [[ "$(context)" == *"as soon as workspace.sh prints your path"* ]]
  [[ "$(context)" == *"after each commit"* ]]
}

@test "stop mode removes that agent's state and claim files and keeps its notes" {
  hook "${AGENT}"
  compact
  hook "${AGENT}"
  printf 'GOAL: keep me\n' >"${NOTES}"
  dir="${CLAUDE_PROJECT_DIR}/.agent-progress"
  [ -e "${dir}/builder-${AGENT}.state" ]
  compgen -G "${dir}/builder-${AGENT}.claim-*" >/dev/null
  stop_hook "${AGENT}"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ ! -e "${dir}/builder-${AGENT}.state" ]
  if compgen -G "${dir}/*.claim-*" >/dev/null; then return 1; fi
  [ "$(cat "${NOTES}")" = "GOAL: keep me" ]
}

@test "stop mode leaves other agents' files alone" {
  hook "${AGENT}"
  hook other-agent
  hook "${AGENT}-2"
  dir="${CLAUDE_PROJECT_DIR}/.agent-progress"
  stop_hook "${AGENT}"
  [ -e "${dir}/builder-other-agent.state" ]
  [ -e "${dir}/builder-other-agent.claim-0" ]
  [ -e "${dir}/builder-${AGENT}-2.state" ]
  [ -e "${dir}/builder-${AGENT}-2.claim-0" ]
}

@test "stop mode with a bad agent_id is a silent no-op" {
  hook "${AGENT}"
  dir="${CLAUDE_PROJECT_DIR}/.agent-progress"
  for bad in "../x" "a/b" "a b" 'a$b' "a.b" "" "*"; do
    stop_hook "${bad}"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
  done
  [ -e "${dir}/builder-${AGENT}.state" ]
  [ -e "${dir}/builder-${AGENT}.claim-0" ]
}

@test "stop mode with no agent_id or malformed stdin is a silent no-op" {
  hook "${AGENT}"
  run --separate-stderr bash "${SCRIPT}" stop <<<'{"session_id":"sess1"}'
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  run --separate-stderr bash "${SCRIPT}" stop <<<'not json'
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -e "${CLAUDE_PROJECT_DIR}/.agent-progress/builder-${AGENT}.state" ]
}

@test "stop mode does not follow or delete a symlinked state file" {
  dir="${CLAUDE_PROJECT_DIR}/.agent-progress"
  printf 'x\n' >"${TMP}/target.state"
  ln -s "${TMP}/target.state" "${dir}/builder-${AGENT}.state"
  : >"${dir}/builder-${AGENT}.claim-0"
  stop_hook "${AGENT}"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -L "${dir}/builder-${AGENT}.state" ]
  [ -e "${dir}/builder-${AGENT}.claim-0" ]
  [ "$(cat "${TMP}/target.state")" = "x" ]
}

@test "stop mode does not follow a symlinked claim file or folder" {
  dir="${CLAUDE_PROJECT_DIR}/.agent-progress"
  printf 'x\n' >"${TMP}/target.claim"
  ln -s "${TMP}/target.claim" "${dir}/builder-${AGENT}.claim-0"
  : >"${dir}/builder-${AGENT}.state"
  stop_hook "${AGENT}"
  [ -L "${dir}/builder-${AGENT}.claim-0" ]
  [ -e "${TMP}/target.claim" ]

  rm -rf "${dir}"
  mkdir "${TMP}/elsewhere"
  : >"${TMP}/elsewhere/builder-${AGENT}.state"
  ln -s "${TMP}/elsewhere" "${dir}"
  stop_hook "${AGENT}"
  [ -e "${TMP}/elsewhere/builder-${AGENT}.state" ]
}

@test "stop mode without CLAUDE_PROJECT_DIR is silent" {
  hook "${AGENT}"
  dir="${CLAUDE_PROJECT_DIR}/.agent-progress"
  unset CLAUDE_PROJECT_DIR
  stop_hook "${AGENT}"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -e "${dir}/builder-${AGENT}.state" ]
}

@test "stop mode does not create the notes folder" {
  rmdir "${CLAUDE_PROJECT_DIR}/.agent-progress"
  stop_hook "${AGENT}"
  [ ! -e "${CLAUDE_PROJECT_DIR}/.agent-progress" ]
}
