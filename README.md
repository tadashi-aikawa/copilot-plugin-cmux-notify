# copilot-plugin-notify

Copilot CLI hook events are emitted as OSC 777 notification escape sequences; listeners such as cmux can consume these notifications.

Tested on macOS only.

## Install

```bash
git clone https://github.com/tadashi-aikawa/copilot-plugin-notify.git
cd <parent directory of copilot-plugin-notify>
copilot plugin install ./copilot-plugin-notify
```

## Test

```bash
bash tests/notify_test.sh
```

## Environment variables


| Name                                         | Description                                                                                     | Default                     |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------- | --------------------------- |
| `COPILOT_NOTIFY_DEBUG`                       | set to `1` to enable debug logging (input/debug log + extra `agentStop` dump)                 |                             |
| `COPILOT_NOTIFY_DEBUG_PATH`                  | debug log path used when `COPILOT_NOTIFY_DEBUG=1`                                              | `/tmp/copilot-notify.jsonl` |
| `COPILOT_NOTIFY_FORCE_STDOUT`                | set to `1` to emit OSC 777 to stdout instead of `/dev/tty`                                     | `0`                         |
| `COPILOT_NOTIFY_AGENTSTOP_POLL_ATTEMPTS`     | number of retries when waiting for the latest `assistant.message` after `agentStop`            | `10`                        |
| `COPILOT_NOTIFY_AGENTSTOP_POLL_INTERVAL_SEC` | interval seconds between retries                                                                | `0.05`                      |
| `COPILOT_NOTIFY_AGENTSTOP_ACCEPTABLE_AGE_MS` | maximum age from hook input timestamp for candidate messages to avoid stale notifications       | `3000`                      |

## Developer notes

### Files

- `plugin.json`: Plugin metadata
- `hooks.json`: Registers `notification`, `preToolUse` and `agentStop` hooks
- `scripts/notify.sh`: Reads hook payload from stdin and emits OSC 777 notification sequences to /dev/tty

### Notes

- Hook payload is read from stdin (JSON).
- `notification` hook:
  - fires when Copilot CLI pauses for human confirmation (e.g. tool execution permission).
  - emits the `message` field from the payload as an OSC 777 notification.
- `ask_user` / `exit_plan_mode` / `task_complete` (via `preToolUse`):
  - notify with normalized `question` / `summary`.
- `agentStop`: notify when Copilot finishes an agent turn and waits for user input.
