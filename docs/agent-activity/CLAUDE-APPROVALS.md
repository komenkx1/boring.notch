# Experimental Claude tool approvals

This slice adds a single-use PermissionRequest return channel. It does not send chat messages, answer AskUserQuestion, approve sandbox network prompts, or add permanent permission rules. Codex interaction is unchanged.

## Opt-in setup

Build the package from this repository:

```sh
swift build --package-path Packages/AgentActivityCore --product boring-notch-claude-integration
Packages/AgentActivityCore/.build/debug/boring-notch-claude-integration preview --interactive-approvals
Packages/AgentActivityCore/.build/debug/boring-notch-claude-integration install --interactive-approvals
```

Start a new Claude session that loads these settings, with Boring Notch running. Hook configuration does not guarantee every Claude surface exposes PermissionRequest. In particular, ordinary noninteractive print mode may deny without waiting for this hook. Other permission hosts may race the hook, and the first decision can win.

To return to observation only, run the same install command without `--interactive-approvals`. To remove the integration, use `uninstall`. The installer preserves unrelated hook handlers, keeps the existing status-line wrapper behavior and one-time backup, and recognizes both owned forwarding commands during removal. Preview does not change settings.

Interactive mode changes only the owned PermissionRequest handler to `request-permission`, with a 55-second hook timeout. Other owned hooks remain observational. Interactive mode has not been enabled globally during this slice's verification.

## Request flow

1. The command forwards the documented observational hook, then registers a bounded interactive request using the installed bearer token.
2. The loopback receiver creates a random ticket for this invocation. PermissionRequest does not supply a tool-use identifier, so a session ID alone is insufficient to correlate decisions.
3. The notch shows the requested tool, working directory and complete normalized tool-input JSON. Allow once and Deny record a choice only for the current matching ticket. Keyboard focus scrolls the controls into view.
4. The waiting command polls and consumes that choice once. It emits Claude's documented PermissionRequest decision JSON on stdout. It does not emit updatedInput or updatedPermissions.

The initial tool set is Bash, Read, Write, Edit, Glob and Grep. Unsupported input or tools return to the provider's normal permission handling. Tool inputs exceeding 8 KiB are not truncated into an approvable request. At most 16 tickets are retained, with one current ticket per observed run. Parallel requests for the same run replace the older ticket, which falls back to Claude.

Tickets expire after 45 seconds and require polling within three seconds. The client stops waiting after 44 seconds, allowing margin before hook cancellation. Transport failure, cancellation, replacement, lifecycle events and app restart return no permission decision. With no decision, Claude controls its usual permission flow, which may deny in noninteractive mode. The UI removes controls once the ticket is absent, directing the user back to Claude. It does not infer process death from missed polling.

The native action requires a key-capable notch panel, using the existing restriction that excludes SkyLight lock-screen mode. Lock-screen runtime behavior has not been tested.

## Transport and privacy

All routes use the existing authenticated loopback receiver and 64 KiB request bound. POST `/v1/claude/approvals` registers; GET `/v1/claude/approvals/<ticket>` polls. There is no HTTP decision endpoint. The shared bearer secret permits registration and reads, not native UI decisions. This is not protection against arbitrary malicious code already running as the same local user.

Full tool inputs stay in bounded memory until ticket removal. They are not included in the sanitized activity snapshot or persisted by the app. The permission command writes only a selected decision to Claude stdout. Existing summary privacy boundaries still apply.

## Verification boundary

The macOS Debug build, package tests, actual loopback command round-trip, and native button/keyboard fixture flows were exercised. Fixture sessions are explicitly labeled FIXTURE. The installed first-party Claude binary is version 2.1.284. During the permission-host live test it reported no login, so a live Claude tool execution receiving a notch decision has not been verified. Claude Desktop's approval return channel is also unverified. Do not promote this slice as live-provider approval support until both sides of a real permission exchange are observed.

The decision shape follows [Claude's official hook reference](https://code.claude.com/docs/en/hooks#permissionrequest-decision-control).

## License

This source remains GPLv3. Retain LICENSE, NOTICE.md, THIRD_PARTY_LICENSES, MODIFICATIONS.md and docs/GPL-COMPLIANCE.md with distributed source. No binary release was published for this slice. A binary release requires the complete corresponding source for its exact revision.
