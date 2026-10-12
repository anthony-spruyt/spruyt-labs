#!/bin/bash
# Any bad input means no output, so no tool call is blocked.
set -u

input=$(cat)
project=${CLAUDE_PROJECT_DIR:-}
agent_id=$(jq -r '.agent_id // empty' <<<"$input" 2>/dev/null) || exit 0
transcript=$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null) || exit 0

# The id becomes a file name, so accept only a plain identifier
[[ "$agent_id" =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
[[ -n "$project" ]] || exit 0

dir="$project/.agent-progress"
notes="$dir/builder-$agent_id.md"
state="$dir/builder-$agent_id.state"
[[ ! -L "$dir" && ! -L "$notes" && ! -L "$state" ]] || exit 0
mkdir -p "$dir" 2>/dev/null || exit 0

# The hook may be handed the session transcript or the subagent's own
sub=""
if [[ "$transcript" == */subagents/agent-*.jsonl ]]; then
  sub=$transcript
elif [[ "$transcript" == *.jsonl ]]; then
  sub="${transcript%.jsonl}/subagents/agent-$agent_id.jsonl"
fi
count=0
if [[ -n "$sub" && -r "$sub" ]]; then
  count=$(grep -cF '"subtype":"compact_boundary"' "$sub" 2>/dev/null || true)
fi
[[ "$count" =~ ^[0-9]+$ ]] || count=0

emit() {
  jq -n --arg c "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $c}}'
}

# Parallel calls race: one claims each count by exclusive create (mkdir is not atomic on virtiofs)
claim() { (
  set -C
  : >"$dir/builder-$agent_id.claim-$count"
) 2>/dev/null; }

if [[ ! -e "$state" ]]; then
  claim || exit 0
  printf '%s\n' "$count" >"$state" 2>/dev/null || exit 0
  emit "Your progress notes file is $notes (none written yet). For multi-step jobs, keep notes there; the folder is gitignored."
  exit 0
fi

seen=$(head -c 20 "$state" 2>/dev/null || true)
seen=${seen//[^0-9]/}
[[ "$count" -gt "${seen:-0}" ]] || exit 0
claim || exit 0
printf '%s\n' "$count" >"$state" 2>/dev/null || exit 0

if [[ ! -s "$notes" ]]; then
  emit "Your context was compacted. Your progress notes file is $notes (none written yet)."
  exit 0
fi

# Hook context is capped at 10,000 characters
body=$(head -c 9000 "$notes")
if [[ "$(wc -c <"$notes")" -gt 9000 ]]; then
  body+=$'\n\n'"[truncated - read the rest of $notes]"
fi
emit "Your context was compacted. Your progress notes are in $notes. Check them against git log before acting on them."$'\n\n'"$body"
exit 0
