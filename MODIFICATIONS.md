# Modification record

This file provides a prominent summary of changes made to the upstream GPLv3 project. Git history remains the detailed record.

## 2026-10-08

- Fixed first-click permission actions to acquire an eligible visible notch panel instead of requiring it to already be the key window. SkyLight panels remain excluded by the existing key-capability check.
- Verified real first-party Claude CLI PermissionRequest allow and deny exchanges through a stdio permission host: allow executed the requested local printf; deny returned the notch denial message without executing it. Desktop approval remains unverified.
- Verified the opt-in interactive handler installed in local user settings after explicit user approval, preserving the model and unrelated configuration. A new CLI session returned the requested printf output through the installed handler.

- Added an experimental, opt-in Claude PermissionRequest return channel with native Allow once and Deny controls, full bounded tool-input review, keyboard focus scrolling, and single-use in-memory tickets.
- Added approval expiry, polling freshness, session replacement and lifecycle cancellation checks, authenticated registration/polling, and no HTTP decision endpoint or permanent permission writes.
- Added reversible interactive-hook installation and focused approval/client/installer tests. Local hook round-trip and UI fixtures were exercised; live Claude approval and Desktop return-channel validation remain pending authentication.

- Added explicit previous/next quota-window navigation, visible scroll indicators, keyboard activation, and Escape dismissal. Enabled key-window focus only for Agent Activity outside lock-screen SkyLight mode.
- Added five-minute observation freshness, an explicit Unknown state, and fresh-event recovery without inferring process death or completion.
- Added multi-provider concurrent receiver and restart tests, and verified live Claude/Codex completion plus a force-stopped Codex session expiring to Unknown.
- Added read-only Codex app-server account quota reads, bounded subprocess handling, shared-account remaining percentages, and full local reset dates in the notch.
- Kept account usage separate from session liveness and added stdio, malformed-response, missing-window, error, and timeout tests.
- Added provider labels to run rows and scrollable detail content to preserve the existing notch header layout.
- Added Codex CLI hook decoding, authenticated ingestion, and a previewable, reversible hook installer that preserves unrelated settings.
- Added provider-aware notch labels and separate Codex subagent identities; hook approvals remain observational and quota remains unavailable.
- Added a private installed-token copy for the Codex forwarder and shared app receiver, plus adapter and installer regression tests.
- Added a native Agent Activity entry point to the open-notch header and a provider-neutral monitoring view for real Claude sessions, attention states, responses, and usage windows.
- Added explicit loading, empty, and bridge-unavailable states plus keyboard and VoiceOver labels for the new controls.
- Started the authenticated Claude receiver with the macOS application lifecycle on fixed loopback port `48763`.
- Added a Claude integration CLI with exact redacted preview, idempotent install, targeted uninstall, and a one-time settings backup.
- Preserved existing Claude hooks and status-line output while adding local event and usage forwarding.
- Used command hook forwarders so `SessionStart` works on Claude versions that skip direct HTTP hooks for that event.
- Added tests for settings preservation, idempotency, legacy-hook migration, status-line restoration, and user replacements.
- Installed and exercised the Claude integration locally without adding agent UI or Codex support.
- Added an authenticated, sanitized activity inspector for non-UI runtime verification.
- Verified first-party Claude CLI lifecycle and real status-line usage windows, plus Claude Desktop lifecycle and permission attention events.
- Classified Claude Desktop's documented `permission_prompt` notification as an approval request while keeping hook-based approvals observational.

## 2026-10-07

- Established the agent activity product scope and staged delivery plan.
- Defined a provider-neutral event envelope for Codex, Claude, and future adapters.
- Added privacy and local transport requirements for agent event ingestion.
- Added a GPLv3 distribution checklist and fork notice.
- Configured the app target to include `LICENSE`, `NOTICE.md`, and `THIRD_PARTY_LICENSES` in its resources.
- Added a Claude-first `AgentActivityCore` Swift package with normalized lifecycle, attention, response, and usage models.
- Added an authenticated loopback HTTP receiver with a Keychain-backed per-install bearer token and bounded request parsing.
- Added documented Claude hook and status-line decoders plus fixture-driven lifecycle, authentication, malformed-body, and size-limit tests.
- Linked the local runtime package into the macOS app target without adding agent UI yet.
