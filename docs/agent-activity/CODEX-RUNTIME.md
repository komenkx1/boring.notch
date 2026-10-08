# Codex CLI monitoring

The Codex adapter forwards documented command-hook events to the authenticated loopback receiver at `127.0.0.1:48763`. It shares the existing Agent Activity view with Claude. It does not launch or control Codex sessions.

## Install and remove

From the repository root:

```sh
swift run --package-path Packages/AgentActivityCore boring-notch-codex-integration preview
swift run --package-path Packages/AgentActivityCore boring-notch-codex-integration install
```

Installation merges this fork's handlers into `~/.codex/hooks.json`, preserves unrelated handlers and settings, and saves a one-time `hooks.json.boring-notch-backup`. Review and trust the Boring Notch handlers with `/hooks` in Codex before starting a new session. The installer does not disable hook trust checks.

```sh
swift run --package-path Packages/AgentActivityCore boring-notch-codex-integration uninstall
```

Removal targets only this integration's exact handler command, executable, and token copy. The backup and unrelated hooks remain. Reinstalling does not duplicate the handlers.

## Observed events

- `SessionStart`, `SubagentStart`: start a session or a separately identified child agent.
- `UserPromptSubmit`, `PreToolUse`, `PostToolUse`: update activity and tool names.
- `PermissionRequest`: display an observational approval request; answer in Codex.
- `Stop`, `SubagentStop`: display the final assistant message, capped at 2,000 characters.
- `Interrupt`: mark the run interrupted.
- `SessionEnd`: complete the session without erasing its final response.

The adapter reads documented session, agent, model, working-directory, event, tool-name, and final-message fields only. It does not read prompts, tool arguments, or private transcripts. Forwarding returns neutral `{}` output, has a one-second HTTP timeout, and fails open if the app is unavailable. Events are kept in memory, not replayed after an app restart.

## Authentication

The installer reuses the bridge's Keychain token, or an explicitly supplied `BORING_NOTCH_AGENT_TOKEN`. The forwarder reads a private `~/.codex/boring-notch-codex-token` copy with mode `0600`; its executable has mode `0700`. The app uses this installed token when present and otherwise uses Keychain. Keep the token private and install Claude and Codex against the same bridge token.

## Verification and limits

On 2026-10-08, Codex CLI `0.144.6` with ChatGPT authentication emitted real session-start and prompt activity into the app's store; the notch displayed Codex, its model label, running state, and an explicit unavailable-usage message. A second short invocation completed, and the notch showed `Completed` with its actual final answer, `notch integration ready.` These checks used ephemeral, read-only invocations with `--ignore-user-config` and a one-invocation `--dangerously-bypass-hook-trust` for the reviewed local handlers. That flag is not part of the installation or recommended normal use.

Unit tests cover completion, final-response preservation, subagent identity, observational approval, malformed and unauthenticated requests, and reversible installation. Live tool, approval, interruption, and subagent paths must be checked separately before claiming live verification of each path. The longer tool-request verification was stopped after it did not finish promptly. Its SIGINT termination did not deliver a terminal hook, leaving the in-memory run marked active. Hooks alone cannot guarantee process liveness after abrupt termination; stale-run reconciliation remains follow-up work.

Hooks do not supply account usage windows or token-by-token streaming. Codex usage therefore remains unavailable, not an invented percentage. Codex Desktop support and app-server streaming, quota reads, and interactive approvals are later work.

Contract reference: [official Codex hooks documentation](https://learn.chatgpt.com/docs/hooks).
