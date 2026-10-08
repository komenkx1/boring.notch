# Agent activity in the macOS notch

## Outcome

Extend this Boring Notch fork so a Mac user can glance at the notch and understand which supported coding agents are working, which need attention, what they most recently reported, and which usage windows are available.

The app is a local activity surface. It is not a replacement terminal, a universal transcript recorder, or a screen scraper.

## Supported capability matrix

| Capability | Codex hooks | Codex app server | Claude hooks | Claude status line |
| --- | --- | --- | --- | --- |
| Run started and stopped | Yes | Yes | Yes | Snapshot only |
| Tool activity | Yes | Yes | Yes | Snapshot only |
| Approval or permission needed | Yes | Yes, interactive | Yes | No |
| Final assistant response | Stop event | Streamed events | MessageDisplay or Stop | No |
| Live response streaming | No | Yes | Yes, with MessageDisplay | No |
| Usage windows | Separate account query | Yes | Provider event dependent | Yes when supplied |
| Existing provider UI remains primary | Yes | Optional | Yes | Yes |

Support in the table means the provider exposes an intended integration path. Each adapter still needs live verification before a release claims the capability.

## Normalized flow

```text
Codex hooks / Codex app server / Claude hooks / Claude status line
                              |
                              v
                   provider-specific adapter
                              |
                              v
                   authenticated local bridge
                              |
                              v
                     AgentActivityStore
                              |
                              v
                  compact notch and expanded view
```

Provider adapters emit the versioned envelope in `event-schema-v1.json`. The shared store must not parse provider-native messages.

## Domain model

An agent run has:

- a stable `agentRunIdentifier`
- a provider and optional model label
- a working directory and optional repository label
- an activity state
- a short, provider-supplied summary
- zero or one pending attention request
- zero or more usage windows
- last event and last activity timestamps

The initial activity states are `starting`, `running`, `waitingForApproval`, `waitingForUser`, `completed`, `failed`, and `interrupted`.

## Local bridge

The first implementation should be a small local receiver owned by the app or a bundled helper.

- Prefer a Unix domain socket. Loopback HTTP is acceptable when provider hook tooling cannot write to a socket.
- Generate a per-install secret and store it in Keychain.
- Reject unauthenticated, oversized, malformed, expired, or unsupported-version events.
- Limit request bodies and stored summaries. Do not store full prompts or transcripts by default.
- Never bind to a non-loopback interface.
- Keep an in-memory recent-event buffer first. Persist only user-approved history later.

## Provider adapters

### Codex hooks

Hooks provide low-friction observation for Codex CLI and app sessions that load the configured hook. They are suitable for lifecycle, tool activity, approvals, interruption, and final-response summaries. They do not provide token-by-token response streaming.

Hook installation must merge only this fork's entries into user or project Codex configuration. The installer must show the exact changes and provide a complete uninstall path.

### Codex app server

App server is the rich integration path for sessions launched or managed by this fork. It supports streamed thread events, approval conversations, and account rate-limit reads. This path is a later phase because it makes the app a richer Codex client and requires stricter lifecycle and error handling.

### Claude hooks

Claude hooks provide lifecycle, permission, tool, subagent, notification, and stop events across supported local Claude surfaces. The adapter should use only documented fields and must tolerate version additions.

### Claude status line

The status-line input can provide workspace, model, context, and account usage-window snapshots when Claude supplies them. The integration should tee only the required fields into the local bridge and preserve the user's existing status-line behavior.

## Interaction model

The compact notch shows only the highest priority signal:

1. an agent waiting for user action
2. a failed or interrupted run
3. the active run with the most recent activity
4. the most recently completed run

The expanded view will list active runs and show provider, task summary, elapsed time, attention state, and usage windows. Approval controls appear only when the provider path supports a safe response channel. Observational hook events must never render a control that pretends it can approve a request.

Text entry in the notch requires a deliberate key-capable window state. The existing non-activating window behavior must remain for passive display and change only while the user is interacting with a supported prompt.

## Privacy defaults

- Local processing only.
- No analytics containing prompts, responses, repository names, or paths.
- Summaries are opt-in for persistence and can be cleared.
- Provider configuration changes are explicit and reversible.
- Logs redact secrets, authorization headers, raw prompts, and full filesystem paths.

## Delivery stages

### Stage 1: foundation and licensing

- Fork and establish an upstream remote.
- Add source-of-truth architecture and event schema.
- Add GPLv3 notices, modification record, release checklist, and bundled legal files.
- Verify an unsigned Debug build.

### Stage 2: local runtime core

- Add normalized Swift models and decoding tests.
- Implement the authenticated local receiver and `AgentActivityStore`.
- Add fixture-driven lifecycle, body-limit, malformed-input, and privacy-boundary tests.

Stage 2 was implemented Claude-first. The runtime now also accepts documented Codex command-hook events through a separate adapter. See `CODEX-RUNTIME.md` for installation and verification boundaries.

### Stage 3: provider observation

- Add opt-in Claude hooks and status-line integration first.
- Verify Claude CLI and Desktop paths separately. Report unsupported fields honestly.
- Add opt-in Codex hooks installation and removal after the Claude path is complete.

The Claude-first provider observation is implemented. The app starts an authenticated fixed-port loopback receiver, while a previewable installer merges command hooks and a status-line forwarder into the user's existing Claude settings. First-party Claude CLI lifecycle, real status-line usage windows, Claude Desktop lifecycle, and a Desktop permission prompt have been exercised locally. A sanitized authenticated inspector exposes the resulting in-memory state without prompts, responses, or filesystem paths. Claude Desktop did not execute the status-line command during validation, so direct Desktop model and usage fields remain unsupported rather than inferred from private files or screen scraping. The Stage 4 notch view now consumes this state. Codex CLI hooks have their own reversible installer and adapter; Codex Desktop and rich app-server integration remain later work.

### Stage 4: notch experience

- Agree on design direction and interaction priorities before UI work.
- Add compact attention state and expanded active-run list.
- Add empty, loading, disconnected, malformed-event, and provider-unavailable states.
- Validate keyboard input, VoiceOver labels, window focus, multiple displays, and no-notch Macs.

The first Stage 4 slice is implemented. A terminal icon in the open-notch header shows real active or attention counts and opens a provider-neutral run list backed by `AgentActivityStore`. The detail view shows Claude state, provider-supplied summaries, and documented usage windows, with explicit loading, empty, and bridge-unavailable states. Observational Claude events remain read-only: the view directs the user back to Claude instead of rendering a non-functional approval control. Multiple-display and no-notch Mac validation remain release checks.

### Stage 5: rich clients and release

- Add optional Codex app-server sessions for streaming and in-notch approvals.
- Add usage-window refresh and reset dates where provider APIs expose them.
- Rename fork branding and identifiers where distribution requires separation.
- Produce a GPL-compliant tagged source and binary release with checksums.

## Acceptance boundary for the first usable milestone

The first Claude milestone is complete when a real Claude hook can create, update, request attention for, and finish an agent run in the local store; a malformed or unauthenticated event is rejected; usage snapshots are accepted when Claude supplies them; and the app remains functional when Claude is not installed. Codex support is the next provider milestone.
