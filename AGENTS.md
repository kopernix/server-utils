# Agent Instructions

These instructions apply to Codex, Claude Code, Cursor, OpenCode, and other coding agents working in this repository.

## Scope

- Read `AGENTS.md`, `README.md`, and the affected script before modifying anything.
- Do not add functionality that was not explicitly requested.
- Do not turn this repository into a framework, configuration system, installer, or complete automation suite.
- Keep every utility independent.
- Do not share code between scripts unless there is a real need and explicit authorization.
- Do not modify other repositories.
- Do not create tags or releases unless explicitly requested.

## Compatibility

- Do not assume that Ubuntu and Debian have exactly the same configuration.
- Verify the distribution, version, and relevant services before making changes.

## Bash

Use strict Bash mode when appropriate:

```bash
set -Eeuo pipefail
IFS=$'\n\t'
```

- Validate all user-provided input.
- Clearly show the operations that will be performed before applying changes.
- Ask for confirmation before destructive actions.
- Do not hide errors.
- Never run destructive scripts during testing outside disposable machines.
- Use ShellCheck when available.

## Documentation and attribution

- Keep documentation and script output in English.
- Preserve the MIT license and the credit `Joan Puiggali aka kopernix`.
