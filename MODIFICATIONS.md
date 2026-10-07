# Modification record

This file provides a prominent summary of changes made to the upstream GPLv3 project. Git history remains the detailed record.

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
