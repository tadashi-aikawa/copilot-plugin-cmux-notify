#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NOTIFY_SCRIPT="$ROOT_DIR/scripts/notify.sh"

PASS_COUNT=0
FAIL_COUNT=0
TMP_FILES=()

visible_output() {
  printf '%s' "$1" | sed -n l
}

run_notify() {
  local input="$1"
  shift || true
  printf '%s' "$input" | env COPILOT_NOTIFY_FORCE_STDOUT=1 "$@" bash "$NOTIFY_SCRIPT"
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL: %s\n' "$1"
  printf '  output: %s\n' "$(visible_output "$2")"
}

assert_notify() {
  local case_name="$1"
  local input="$2"
  local expected="$3"
  shift 3 || true

  local output
  if ! output="$(run_notify "$input" "$@")"; then
    fail "$case_name (script failed)" ""
    return
  fi

  if ! printf '%s' "$output" | grep -Fq 'notify;Copilot;'; then
    fail "$case_name (notify not emitted)" "$output"
    return
  fi
  if ! printf '%s' "$output" | grep -Fq "$expected"; then
    fail "$case_name (expected body not found: $expected)" "$output"
    return
  fi

  pass "$case_name"
}

assert_no_notify() {
  local case_name="$1"
  local input="$2"
  shift 2 || true

  local output
  if ! output="$(run_notify "$input" "$@")"; then
    fail "$case_name (script failed)" ""
    return
  fi

  if printf '%s' "$output" | grep -Fq 'notify;Copilot;'; then
    fail "$case_name (unexpected notify emitted)" "$output"
    return
  fi

  pass "$case_name"
}

require_commands() {
  local missing=0
  local cmd
  for cmd in bash jq sed grep; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      printf 'Missing required command: %s\n' "$cmd"
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    exit 1
  fi
}

cleanup() {
  local file
  for file in "${TMP_FILES[@]}"; do
    if [ -n "$file" ] && [ -e "$file" ]; then
      rm -f "$file"
    fi
  done
}

main() {
  require_commands

  assert_notify \
    "notification: messageを通知する" \
    '{"hook_event_name":"Notification","message":"Path permission needed: /Users/test","title":"Permission needed","notification_type":"permission_prompt"}' \
    "Path permission needed: /Users/test"

  assert_no_notify \
    "notification: messageが空なら通知しない" \
    '{"hook_event_name":"Notification","message":"","title":"Permission needed","notification_type":"permission_prompt"}'

  assert_notify \
    "ask_user: 改行は空白に正規化される" \
    '{"toolName":"ask_user","toolArgs":{"question":"line1\nline2"}}' \
    "line1 line2"

  assert_notify \
    "exit_plan_mode: 改行は空白に正規化される" \
    '{"toolName":"exit_plan_mode","toolArgs":{"summary":"done\nnext"}}' \
    "done next"

  assert_notify \
    "task_complete: 改行は空白に正規化される" \
    '{"toolName":"task_complete","toolArgs":{"summary":"done\nnext"}}' \
    "done next"

  local transcript_path
  transcript_path="$(mktemp)"
  TMP_FILES+=("$transcript_path")
  cat >"$transcript_path" <<'EOF'
{"type":"assistant.message","timestamp":"2026-02-24T12:00:00.000Z","data":{"toolRequests":[],"content":"agent finished"}}
EOF

  local agent_stop_input
  agent_stop_input="$(
    jq -nc --arg transcript "$transcript_path" '
      {
        stopReason: "end_turn",
        timestamp: "2026-02-24T12:00:00.000Z",
        transcriptPath: $transcript,
        data: { toolRequests: [] }
      }
    '
  )"
  assert_notify \
    "agentStop: transcriptのassistant.messageを通知する" \
    "$agent_stop_input" \
    "agent finished" \
    COPILOT_NOTIFY_AGENTSTOP_POLL_ATTEMPTS=1

  assert_no_notify \
    "report_intent: 通知しない" \
    '{"toolName":"report_intent"}'

  assert_no_notify \
    "preToolUse: その他のツールは通知しない" \
    '{"toolName":"bash","toolArgs":{"command":"git status"}}'

  printf '\nSummary: PASS=%d FAIL=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
  if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
  fi
}

trap cleanup EXIT
main "$@"
