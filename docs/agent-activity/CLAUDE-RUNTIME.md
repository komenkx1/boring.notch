# Claude runtime contract

Stage 2 provides the receiving and normalization layer for Claude. It does not change the user's Claude configuration yet. Hook and status-line installation stays opt-in for Stage 3.

## Local endpoints

The app-owned receiver listens only on IPv4 loopback. The selected port is supplied by the running app.

| Endpoint | Input |
| --- | --- |
| `POST /v1/hooks/claude` | One documented Claude hook JSON body |
| `POST /v1/status/claude` | One documented Claude status-line JSON snapshot |

Both endpoints require:

- `Authorization: Bearer <per-install-token>`
- `Content-Type: application/json`
- a body no larger than 65,536 bytes by default

The bearer token is generated from 32 random bytes and stored as a generic password in Keychain with `AfterFirstUnlockThisDeviceOnly` accessibility. The token must not be printed in logs, copied into diagnostics, or committed to configuration examples.

## Accepted Claude signals

The hook decoder recognizes lifecycle, prompt processing, streamed `MessageDisplay` batches, tool use, permission requests, notifications, elicitation, subagent activity, task activity, stop, failure, and session-end events. Unknown event fields are ignored so additive provider changes do not break decoding. Unknown event names are rejected instead of guessed.

Status-line snapshots contribute only these fields:

- session identifier
- model display name
- current working directory
- context-window percentage
- five-hour, seven-day, and spend-limit percentages and reset times when present

Claude may omit account rate limits until after its first API response. The store therefore treats usage windows as optional. Spend-limit percentage is not capped at 100 because Claude can report overage.

## Privacy boundary

- Raw prompts and transcripts are not decoded or stored.
- Hook summaries and assembled assistant responses are length limited in memory.
- Permission events are observational in this stage. They do not expose a fake approval action.
- No history is persisted.
- Stage 3 configuration must show the exact Claude settings changes and provide complete removal.

## Verification boundary

Automated tests cover documented fixture decoding, lifecycle aggregation, response assembly, authentication, malformed JSON, body limits, and HTTP framing. A real Claude CLI and Claude Desktop integration test still belongs to Stage 3 because this stage does not install provider configuration.

## Provider references

- [Claude Code hooks](https://code.claude.com/docs/en/hooks)
- [Claude Code status line](https://code.claude.com/docs/en/statusline)
