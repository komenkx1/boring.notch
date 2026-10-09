# Answering Claude questions in the notch

This opt-in slice answers `AskUserQuestion` through Claude's documented `PreToolUse` hook. It does not send new prompts, inject conversation messages, scrape terminal output, or add a general chat composer. Codex interaction is unchanged.

## Opt-in setup

Build the package, preview the changes, then install only after choosing to enable question responses:

```sh
swift build --package-path Packages/AgentActivityCore --product boring-notch-claude-integration
Packages/AgentActivityCore/.build/debug/boring-notch-claude-integration preview --interactive-approvals --interactive-questions
Packages/AgentActivityCore/.build/debug/boring-notch-claude-integration install --interactive-approvals --interactive-questions
```

Use both flags to keep existing interactive approvals enabled. Each install sets the owned handlers to the modes named in that invocation; omitting a flag disables its interactive mode. To turn off question responses while retaining approvals, install with only `--interactive-approvals`. `uninstall` removes owned handlers and preserves unrelated hooks. Preview is non-mutating, the installer is idempotent, and the existing one-time settings backup is retained.

The questions flag changes the owned `PreToolUse` handler to `request-question`, with a 190-second hook timeout. It immediately forwards non-question tool events observationally. It does not add a second competing owned PreToolUse handler. The approval handler remains separate. Model, other settings, and unrelated hooks are preserved.

Start a new Claude session that loads the installed settings, with Boring Notch running. Existing sessions may have loaded their old hook configuration.

## Official response path

Claude's [hook reference](https://code.claude.com/docs/en/hooks) documents responding to `AskUserQuestion` before tool execution: return `permissionDecision: "allow"` with `updatedInput` containing the original `questions` and an `answers` map. Allow alone is not an answer. The [user-input reference](https://code.claude.com/docs/en/agent-sdk/user-input) defines keys as the full question text, with selected labels or typed text as values. Multiple selections use comma-separated labels.

The helper preserves the original tool input, adds the answers, and emits only the documented hook JSON to Claude stdout. It does not write permanent permission rules. Other hooks still run; their ask or deny decisions can take precedence. Receiving answers at the hook is not a guarantee that every host or another handler will execute the tool.

## Native form

The detail pane shows 1 to 4 questions, each with 2 to 4 text options and a written-answer field. Single-choice questions accept one selection; multi-choice questions allow toggling several. Nonblank typed text replaces selected options for that question. Nothing is selected or submitted automatically. Every question must have an answer before Send answers is enabled.

Question and option text wraps without ellipsis. Keyboard focus reveals its field or action in the existing detail scroll view. Text entry keeps the expanded notch open when the pointer leaves; Escape still dismisses it. The native action acquires an eligible visible key-capable panel, with the same lock-screen exclusion as approvals.

Answer in Claude removes the pending notch ticket and emits no answer or decision. Claude resumes its own input handling. Depending on the host, that can show the original prompt or deny in noninteractive mode; this button does not launch a new session or promise a Desktop focus handoff.

## Bounds and privacy

Question tickets use the existing authenticated loopback registration and polling routes. There is no HTTP answer-writing endpoint. Only the native UI records answers; polling consumes the answer bundle once for the matching random ticket. One current ticket per run and at most 16 total remain the shared limit.

Tickets expire after 180 seconds, require polling within three seconds, and are canceled by replacement, lifecycle changes, bridge loss, or app restart. The helper stops waiting after 179 seconds. Missing or invalid answers return no hook decision and leave handling to Claude.

The original input is bounded to 8 KiB, with additional per-field limits. Each written answer is bounded to 4 KiB, all answer values to 8 KiB, and encoded answers to 16 KiB. Duplicate question texts, duplicate labels, malformed forms, prepopulated answers, oversized inputs, and option HTML previews fall back to Claude rather than becoming partially rendered answerable forms.

Full questions and answers live only in bounded request memory. They are excluded from the sanitized activity snapshot and are not persisted by the app. After submission they are returned to the originating Claude hook, where the provider's own conversation retention applies. This local transport is not protection against arbitrary malicious code running as the same macOS user.

## Verification boundary

Verified with first-party Claude CLI 2.1.284, model `claude-haiku-4-5`, stream-json, manual permissions, and a stdio permission host. The provider received a written answer submitted from the native notch and, in a separate run, single-choice plus multi-choice answers. Tests used isolated settings and did not change the user's model.

Native fixture coverage includes empty-answer disabling, Space selection and deselection, focus/scrolling, and Answer in Claude returning no stdout decision. Package tests cover validation, preservation of input fields, authentication, single-use correlation, expiry, cancellation, privacy, and opt-in installation. Fixtures are labeled FIXTURE and are not live-provider evidence.

Claude Desktop question responses, every ordinary terminal launch mode, lock-screen interactions, multiple displays, and Macs without a hardware notch remain unverified. This is an experimental interaction slice, not a general chat or universal Claude compatibility claim.

## License

This source remains GPLv3. Retain LICENSE, NOTICE.md, THIRD_PARTY_LICENSES, MODIFICATIONS.md, and docs/GPL-COMPLIANCE.md with distributed source. No binary release is published for this slice; distributed binaries require the complete corresponding source for their exact revision.
