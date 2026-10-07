# Repository working agreement

## Product direction

This fork extends Boring Notch with a local agent activity surface for macOS. The notch should show verified activity from supported coding agents, surface requests that need attention, and display usage windows when a provider exposes them.

The product and integration source of truth is `docs/agent-activity/PRODUCT_AND_ARCHITECTURE.md`. The normalized event contract is `docs/agent-activity/event-schema-v1.json`.

## Implementation boundaries

- Preserve existing Boring Notch behavior unless a task explicitly changes it.
- Prefer provider-supported hooks and local protocols. Do not scrape terminal text or use Accessibility APIs to infer agent output.
- Keep provider-specific parsing behind adapters. Views and shared stores consume normalized agent events only.
- Treat prompts, responses, repository paths, and usage information as private local data.
- Bind any local event receiver to a Unix domain socket or loopback interface. Require a per-install secret and validate event size and shape.
- Hook installation must be opt-in, previewable, reversible, and must not overwrite unrelated provider configuration.
- Do not claim that an integration supports streaming, approvals, or usage limits unless the corresponding provider path has been exercised.

## Code style

- Match nearby Swift and SwiftUI conventions before introducing a new pattern.
- Prefer clear business names such as `activeAgentRuns`, `pendingAttentionRequest`, and `usageWindowResetDate`.
- Avoid vague names such as `data`, `result`, `payload`, `temp`, `obj`, and `res` when the domain is known.
- Keep functions small and control flow straightforward. Avoid abstractions that only hide simple logic.
- Reuse existing helpers when they fit. Keep refactors scoped to the files being changed.
- Add comments only for a non-obvious business rule or platform constraint.
- Preserve public API contracts unless the task explicitly requires a change.

## Verification

- Build the `boringNotch` scheme after changing source or project configuration.
- Add focused tests for event decoding, state transitions, authentication, and provider adapters.
- Report the exact provider path that was tested: hook, app server, CLI wrapper, desktop app, or fixture.
- Separate fixture-tested behavior from behavior verified against a live provider.

## Licensing

- This repository remains licensed under GNU GPL version 3.
- Keep `LICENSE`, `NOTICE.md`, `THIRD_PARTY_LICENSES`, and `docs/GPL-COMPLIANCE.md` with distributed source.
- Record material changes in `MODIFICATIONS.md`.
- Do not publish a binary unless the corresponding complete source for that exact version is available under GPLv3.
