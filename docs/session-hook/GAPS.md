---
block: session-hook
doc: GAPS
verified_against: 8b3075f
verified_on: 2026-09-24
---

# Gaps

Debt and unenforced boundaries in this block. Fixing any of these does not
change a contract or an invariant recorded elsewhere in this block.

## SessionStart `additionalContext` delivery is a known-unreliable channel

The script's own comment names two upstream trackers:
`scripts/session-start.sh::"anthropics/claude-code #16538"` and
`scripts/session-start.sh::"VS Code #88086"`, and states the hook is
`scripts/session-start.sh::"best-effort"` while the skill is the robust driver
`[verified]`. This block cannot fix that; it can only avoid depending on the
hook for anything the skill does not also do on its own. No test in this repo
exercises the actual delivery path into a live session, only that the script
prints the right bytes to stdout `[verified]`.

## The reminder text is prefix-agnostic by omission, not by a checked rule

Nothing in `hooks/hooks.json` or `scripts/session-start.sh` enforces that the
reminder text stay silent about the MCP tool prefix. It currently is
(`scripts/session-start.sh::"durable work-state store"` names the server, not a
prefix) `[verified]`, matching the skill's own two-prefix listing
(`skills/worklog-persist/SKILL.md::"mcp__plugin_worklog-persist_outline__*"`)
`[verified]`, but
a future edit to the reminder text could hardcode `mcp__outline__*` without
failing any test owned by this block. See
[`CONTRACTS.md`](CONTRACTS.md#the-hook-names-the-server-not-a-tool-prefix).

## A renamed install can leave a stale off-marker under the old path

`scripts/persistence-state.sh::state_dir()` hardcodes the literal name
`worklog-persist`. The root `README.md::"The off-state file does not"` line
documents that a user upgrading from the older `outline-persist` plugin has
their old off-marker at a directory this resolver never reads, so persistence
silently resumes after the upgrade unless the user manually re-runs
`persistence-state.sh off` once `[verified]`. Nothing in this block detects or
warns about the stale old-path marker; it is simply orphaned.

## The `path` subcommand has no test coverage

`scripts/persistence-state.sh::"usage: persistence-state.sh {path|status|off|on}"`
lists four subcommands, but `tests/test_offswitch.sh` only calls `status`,
`off`, and `on`. `path` is untested at the pin `[verified]`.

## Unwritable state directory has no friendly error path

`scripts/persistence-state.sh` runs under `set -euo pipefail`. The `off` command
calls `mkdir -p "$(state_dir)"` before writing the marker; if the resolved
parent directory is not writable, `mkdir` fails and the script aborts on
`errexit` with `mkdir`'s own stderr message, not a `worklog-persist:`-prefixed
one `[inferred]` from the script's structure and its shell options. No test in
this repo constructs an unwritable state directory to exercise this path
`[verified]`.
