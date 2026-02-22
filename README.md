# cmux-notify plugin

Copilot CLI hook events are forwarded to `cmux notify`.

## Files

- `plugin.json`: Plugin metadata
- `hooks.json`: Registers `preToolUse` and `agentStop` hooks
- `scripts/cmux-notify.sh`: Reads hook payload from stdin and calls `cmux notify`

## Install

```bash
copilot plugin install tadashi-aikawa/copilot-plugin-cmux-notify
```

## Notes

- Hook payload is read from stdin (JSON).
- `preToolUse`: notify only for selected tool names (default: `shell,bash`).
- `agentStop`: notify when Copilot finishes an agent turn and waits for user input.

## Environment variables

- `CMUX_NOTIFY_PRETOOL_TOOLS`: comma-separated tool names for `preToolUse` notifications (default: `shell,bash`)
- `CMUX_NOTIFY_DEBUG`: set to `1` to append `agentStop` payload JSON into `/tmp/cmux-notify-agent-stop.jsonl`
