# Claude runtime contract

Stage 3 connects the Stage 2 receiver to Claude Code. Installation is explicit, previewable, idempotent, and reversible. The Stage 4 notch view reads the normalized in-memory state produced by this runtime.

## Local endpoints

The app-owned receiver listens only on IPv4 loopback at `127.0.0.1:48763`. A fixed port lets Claude's user-level hooks work for CLI, IDE, and Desktop sessions without rewriting settings on every app launch.

| Endpoint | Input |
| --- | --- |
| `POST /v1/hooks/claude` | One documented Claude hook JSON body |
| `POST /v1/status/claude` | One documented Claude status-line JSON snapshot |
| `GET /v1/agent-runs` | Sanitized in-memory activity snapshot for local inspection |

Both endpoints require:

- `Authorization: Bearer <per-install-token>`
- `Content-Type: application/json`
- a body no larger than 65,536 bytes by default

The bearer token is generated from 32 random bytes and stored as a generic password in Keychain with `AfterFirstUnlockThisDeviceOnly` accessibility. Claude also needs the token in its user settings so the forwarding command inherits it as `BORING_NOTCH_AGENT_TOKEN`; the installer restricts the settings file to mode `0600`. The token must not be printed in logs, copied into diagnostics, or committed to configuration examples.

## Install, inspect, and remove

Run these commands from the repository root:

```bash
swift run --package-path Packages/AgentActivityCore boring-notch-claude-integration preview
swift run --package-path Packages/AgentActivityCore boring-notch-claude-integration install
swift run --package-path Packages/AgentActivityCore boring-notch-claude-integration inspect
swift run --package-path Packages/AgentActivityCore boring-notch-claude-integration uninstall
```

`preview` prints the exact proposed `~/.claude/settings.json` with the bearer token redacted and does not write files. `install`:

- creates `~/.claude/settings.json.boring-notch-backup` once;
- preserves unrelated settings and existing hook groups;
- installs one command forwarder for each observed Claude event;
- wraps the existing status-line command, if present, and reproduces its output;
- writes private files as mode `0600` and the forwarding executable as mode `0700`.

`uninstall` removes only the Boring Notch hook handlers and token environment entry. It restores the previous status line unless the user replaced the Boring Notch status line after installation. The one-time backup remains available for manual recovery.

`inspect` authenticates with the installed token and prints the receiver's current JSON snapshot. It exposes lifecycle state, provider, model, repository label, attention state, usage windows, and timestamps. It deliberately omits working directories, prompts, response text, and summaries. The command remains a development and diagnostics surface; the notch view reads the same normalized store directly in memory.

The hook transport intentionally uses a command forwarder instead of Claude's direct HTTP hook type. The locally installed Claude runtime skipped direct HTTP hooks for `SessionStart`; command hooks cover that event and still forward the unchanged JSON body to the authenticated loopback endpoint with a one-second timeout.

## Accepted Claude signals

The hook decoder recognizes lifecycle, prompt processing, streamed `MessageDisplay` batches, tool use, permission requests, notifications, elicitation, subagent activity, task activity, stop, failure, and session-end events. A documented `Notification` with `notification_type: permission_prompt` is classified as an approval request so Claude Desktop's delayed permission notification retains the correct attention priority. Unknown event fields are ignored so additive provider changes do not break decoding. Unknown event names are rejected instead of guessed.

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

Automated tests cover documented fixture decoding, lifecycle aggregation, response assembly, authentication, malformed JSON, body limits, HTTP framing, settings preservation, idempotent installation, legacy-hook migration, and targeted removal.

On the development Mac, the built app accepted authenticated hook and status snapshots with HTTP `204` and rejected an incorrect token with `401`. A first-party Claude CLI run using `claude-haiku-4-5` exercised lifecycle hooks and completed successfully. A separate interactive CLI run forwarded a live status-line snapshot containing the model, context percentage, five-hour window, and seven-day window; the inspector preserved those values when the run completed.

Claude Desktop was also exercised against this repository. Its coding session created and completed a run through the installed hooks, and a real file-write permission card produced an attention event. Claude Desktop did not invoke the configured status-line command during that session, so the run had no model label or usage windows in the local store. This limitation is reported rather than filled from Desktop's private session files or scraped from its UI. The CLI status-line path remains the verified source of real Claude account usage in this stage.

## Provider references

- [Claude Code hooks](https://code.claude.com/docs/en/hooks)
- [Claude Code status line](https://code.claude.com/docs/en/statusline)
