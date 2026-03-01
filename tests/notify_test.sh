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

  assert_no_notify \
    "path: cwd配下(絶対)は通知しない" \
    '{"toolName":"edit","cwd":"/tmp/work","toolArgs":{"path":"/tmp/work/a.txt"}}'

  assert_no_notify \
    "path: cwd配下(相対)は通知しない" \
    '{"toolName":"edit","cwd":"/tmp/work","toolArgs":{"path":"a.txt"}}'

  assert_no_notify \
    "path: cwd外でもallowlist一致なら通知しない" \
    '{"toolName":"write","cwd":"/tmp/work","toolArgs":{"path":"/tmp/other/a.txt"}}' \
    COPILOT_NOTIFY_ALLOW_PATHS=/tmp/other

  assert_notify \
    "path: cwd外かつallowlist不一致なら通知する" \
    '{"toolName":"write","cwd":"/tmp/work","toolArgs":{"path":"/tmp/other/a.txt"}}' \
    "write: /tmp/other/a.txt" \
    COPILOT_NOTIFY_ALLOW_PATHS=/tmp/safe

  assert_notify \
    "path: cwd境界(/a vs /abc)は一致しない" \
    '{"toolName":"edit","cwd":"/a","toolArgs":{"path":"/abc/file.txt"}}' \
    "edit: /abc/file.txt"

  assert_notify \
    "path: allowlist境界(/a vs /abc)は一致しない" \
    '{"toolName":"edit","cwd":"/tmp/work","toolArgs":{"path":"/abc/file.txt"}}' \
    "edit: /abc/file.txt" \
    COPILOT_NOTIFY_ALLOW_PATHS=/a

  assert_notify \
    "path: cwd未指定かつ相対pathは通知する" \
    '{"toolName":"edit","toolArgs":{"path":"relative.txt"}}' \
    "edit: relative.txt"

  assert_no_notify \
    "bash: allowルール一致は通知しない" \
    '{"toolName":"bash","toolArgs":{"command":"git status"}}' \
    "COPILOT_NOTIFY_ALLOW_TOOL_RULES=shell(git:*)"

  assert_notify \
    "bash: denyルール一致は通知する" \
    '{"toolName":"bash","toolArgs":{"command":"git push"}}' \
    "bash" \
    "COPILOT_NOTIFY_DENY_TOOL_RULES=shell(git push)"

  assert_no_notify \
    "bash+curl: 許可URLのみなら通知しない" \
    '{"toolName":"bash","toolArgs":{"command":"curl https://api.github.com/repos"}}' \
    "COPILOT_NOTIFY_ALLOW_TOOL_RULES=shell(curl)" \
    COPILOT_NOTIFY_ALLOW_URLS=api.github.com

  assert_notify \
    "bash+curl: 不許可URLが含まれると通知する" \
    '{"toolName":"bash","toolArgs":{"command":"curl https://example.com"}}' \
    "bash" \
    "COPILOT_NOTIFY_ALLOW_TOOL_RULES=shell(curl)" \
    COPILOT_NOTIFY_ALLOW_URLS=api.github.com

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

  assert_notify \
    "path優先: bashでもtoolArgs.pathがあればpath判定を使う" \
    '{"toolName":"bash","cwd":"/tmp/work","toolArgs":{"path":"/tmp/outside.txt","command":"git status"}}' \
    "bash: /tmp/outside.txt" \
    "COPILOT_NOTIFY_ALLOW_TOOL_RULES=shell(git:*)"

  assert_notify \
    "ask_user: toolArgs.pathがあってもquestionを通知する" \
    '{"toolName":"ask_user","cwd":"/tmp/work","toolArgs":{"question":"need approval","path":"a.txt"}}' \
    "need approval"

  assert_notify \
    "exit_plan_mode: toolArgs.pathがあってもsummaryを通知する" \
    '{"toolName":"exit_plan_mode","cwd":"/tmp/work","toolArgs":{"summary":"plan done","path":"a.txt"}}' \
    "plan done"

  assert_notify \
    "task_complete: toolArgs.pathがあってもsummaryを通知する" \
    '{"toolName":"task_complete","cwd":"/tmp/work","toolArgs":{"summary":"task done","path":"a.txt"}}' \
    "task done"

  printf '\nSummary: PASS=%d FAIL=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
  if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
  fi
}

trap cleanup EXIT
main "$@"
