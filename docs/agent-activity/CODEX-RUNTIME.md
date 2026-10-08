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

Initial adapter tests covered completion, final-response preservation, subagent identity, observational approval, malformed and unauthenticated requests, and reversible installation. Approval, interruption, and subagent paths still require live verification before claiming those paths. The initial longer tool-request check was stopped after it did not finish promptly. Its SIGINT termination did not deliver a terminal hook, leaving the in-memory run marked active. The observation-freshness work below addresses indefinite active counts without claiming process-death detection.

## Observation freshness

The shared store marks an active or waiting run `unknown` after five minutes without an activity event. This removes it from active and attention counts without inventing a completion or failure. Its last provider summary and pending prompt remain available for context. A fresh activity event restores the appropriate state. Quota updates do not refresh activity freshness or revive an unknown run.

`Unknown` is observation uncertainty, not process-death detection: a healthy agent can be quiet while thinking or waiting. The app does not inspect private process transcripts. A restart or bridge retry clears the in-memory sessions rather than restoring old active states. Already-running agents reappear only when they emit another event.

On 2026-10-08, a Codex CLI session was force-stopped during a shell tool call. With no terminal hook, it changed from `Running` to `Unknown` after the real five-minute interval. The notch showed the uncertainty explanation and excluded it from active counts. Concurrent first-party Claude Code `2.1.284` using `claude-haiku-4-5` and Codex CLI `0.144.6` using its configured default model both completed with separate final responses. Restarting the app yielded an empty authenticated session snapshot. Concurrent receiver, expiry, recovery, and restart scenarios also have deterministic tests; their simulated clock does not replace the live forced-stop check.

## Shared account usage

After opt-in Codex monitoring installation, the app starts a short-lived local `codex app-server --stdio` process at startup and every five minutes. It performs `initialize`, `initialized`, and `account/rateLimits/read` only, then closes the process. It never creates a thread, starts inference, consumes reset credits, sends notifications, or copies the CLI's authentication secrets. Analytics are explicitly disabled for this child process. Each read has a 15-second timeout and a bounded stdout buffer.

The app-server uses the account already signed into the local Codex CLI. This is account-wide quota, shared across its sessions, not per-session token usage. It is displayed separately from session state and is not merged into hook events. No model-to-bucket mapping is inferred: all supplied buckets retain their provider identifiers or labels. Multiple signed-in accounts or custom launch environments may not match the account of a particular observed session.

The decoder prefers `rateLimitsByLimitId` when supplied, otherwise uses the legacy `rateLimits` bucket. Window duration and reset epoch come from the provider; missing percentages remain unavailable. The UI shows `100 - usedPercent`, bounded to 0–100, as percentage left, and the full local reset date/time. Failed reads clear the displayed snapshot; the UI shows unavailable rather than retaining stale numbers as current. Successful reads show their update time. The diagnostic command is:

```sh
swift run --package-path Packages/AgentActivityCore boring-notch-codex-integration read-usage
```

The real account quota request and its notch display were verified on 2026-10-08. Unit tests cover named and legacy buckets, null/missing windows, malformed fields, reset dates, stdio initialization order, ignored notifications, sanitized server errors, and bounded timeouts. Codex Desktop lifecycle, token-by-token streaming, and interactive approvals remain later work.

Contract reference: [official Codex hooks documentation](https://learn.chatgpt.com/docs/hooks).

Quota reference: [official Codex app-server documentation](https://learn.chatgpt.com/docs/app-server).
