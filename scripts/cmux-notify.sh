#!/usr/bin/env bash
set -euo pipefail

INPUT="$(cat)"

HOOK_EVENT_NAME="$(
  echo "$INPUT" | jq -r '
    .hook_event_name
    // .hookEventName
    // empty
  '
)"

STOP_REASON="$(
  echo "$INPUT" | jq -r '
    .stopReason
    // .stop_reason
    // empty
  '
)"

TRANSCRIPT_PATH="$(
  echo "$INPUT" | jq -r '
    .transcriptPath
    // .transcript_path
    // empty
  '
)"

TOOL_NAME="$(
  echo "$INPUT" | jq -r '
    .toolName
    // .tool_name
    // .tool?.name
    // empty
  '
)"

TITLE="Copilot"
BODY=""
PRETOOL_TOOLS="${CMUX_NOTIFY_PRETOOL_TOOLS:-shell,bash}"
DEBUG_MODE="${CMUX_NOTIFY_DEBUG:-0}"

in_allow_list() {
  local value="$1"
  local list="$2"
  local item

  IFS=',' read -r -a items <<< "$list"
  for item in "${items[@]}"; do
    if [ "$value" = "$item" ]; then
      return 0
    fi
  done
  return 1
}

if [ -n "$TOOL_NAME" ] && [ "$TOOL_NAME" != "null" ] && in_allow_list "$TOOL_NAME" "$PRETOOL_TOOLS"; then
  BODY="Copilot requests tool execution: ${TOOL_NAME}"
elif [ "$HOOK_EVENT_NAME" = "agentStop" ] || [ "$STOP_REASON" = "end_turn" ] || [ -n "$TRANSCRIPT_PATH" ]; then
  if [ "$DEBUG_MODE" = "1" ]; then
    printf '%s\n' "$INPUT" >> /tmp/cmux-notify-agent-stop.jsonl
  fi

  if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    BODY="$(
      jq -r '
        select(.type == "assistant.message")
        | .data.content // empty
      ' "$TRANSCRIPT_PATH" \
        | awk 'length > 0 { line = $0 } END { print line }'
    )"
  else
    BODY="$(
      echo "$INPUT" | jq -r '
        .finalMessage
        // .["last-assistant-message"]
        // .lastAssistantMessage
        // .assistantMessage
        // .message
        // .text
        // .output_text
        // .outputText
        // .response
        // .responseText
        // .content
        // .completion
        // empty
      '
    )"
  fi
fi

if [ -z "$BODY" ] || [ "$BODY" = "null" ]; then
  if [ -n "$TOOL_NAME" ] && [ "$TOOL_NAME" != "null" ] && in_allow_list "$TOOL_NAME" "$PRETOOL_TOOLS"; then
    BODY="Copilot requests tool execution approval"
  elif [ "$HOOK_EVENT_NAME" = "agentStop" ] || [ "$STOP_REASON" = "end_turn" ] || [ -n "$TRANSCRIPT_PATH" ]; then
    BODY="Copilot task completed"
  else
    exit 0
  fi
fi

cmux notify --title "$TITLE" --body "$BODY"
