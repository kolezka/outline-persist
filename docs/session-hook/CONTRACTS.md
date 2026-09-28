---
block: session-hook
doc: CONTRACTS
verified_against: 487ab42
verified_on: 2026-09-28
---

# Contracts

Durable interfaces owned by this block. See [`../CONVENTIONS.md`](../CONVENTIONS.md)
for the `enforcement:` field format.

## `hooks/hooks.json` shape

### The manifest wraps SessionStart in `{"hooks": {"SessionStart": [...]}}`

Claude Code's plugin loader expects a top-level `hooks` object keyed by event
name, each value a list of `{matcher, hooks: [...]}` entries `[verified]`. The
file at the pin has exactly one `SessionStart` entry with `matcher: "*"` and one
command hook (`hooks/hooks.json::"matcher"`) `[verified]`.

enforcement: `tests/test_structure.sh::"hooks.json missing wrapped SessionStart"`
  (fails the suite if `hooks['hooks']['SessionStart']` cannot be indexed) and
  `install.sh::check_structure()` at `--check` time only.

### The command line uses `${CLAUDE_PLUGIN_ROOT}`, never a literal path

`hooks/hooks.json::"${CLAUDE_PLUGIN_ROOT}"` resolves the plugin's own install
directory at run time, supplied by the Claude Code plugin loader, so the same
manifest works regardless of where the plugin was installed `[verified]`.

enforcement: convention. No test in this repo inspects the literal `command`
  string inside `hooks/hooks.json`; `tests/test_structure.sh` only checks that
  the `SessionStart` key exists, not that the manifest invokes it correctly
  `[verified]`.

## `scripts/session-start.sh` output contract

### Emits `hookSpecificOutput.additionalContext` JSON, or nothing

When persistence is on, the script prints one JSON object to stdout with keys
`hookSpecificOutput.hookEventName` set to `"SessionStart"` and
`hookSpecificOutput.additionalContext` set to the reminder string
(`scripts/session-start.sh::"hookSpecificOutput"`,
`scripts/session-start.sh::"hookEventName"`,
`scripts/session-start.sh::"additionalContext"`) `[verified]`. When off, it exits
`0` before printing anything `[verified]`.

enforcement: `tests/test_offswitch.sh::"hook emits when on"` parses the output
  as JSON and indexes both keys, and
  `tests/test_offswitch.sh::"hook silent when off"` asserts the byte count is
  `0`. Both are run-time checks in the offline test suite, not at hook-install
  time.

### The JSON is built with `json.dumps`, never hand-assembled

The reminder text is passed to a `python3` heredoc that calls
`scripts/session-start.sh::"json.dumps"` on a dict, instead of interpolating the
text into a JSON string literal in bash `[verified]`. This keeps embedded quotes
and backticks in the reminder text from producing invalid JSON `[inferred]`.

enforcement: convention. No test feeds the script a reminder string containing
  a double quote or backslash to confirm the escaping holds; the current
  reminder text just happens not to need it `[verified]`.

### The reminder carries the resolved identity, or the reason it has none

After the static rule, the script runs `resolve-context.sh` and appends one
sentence `[verified]`:

- with a `kb_path`: the world, project, KB folder and tasks path
  (`scripts/session-start.sh::"Resolved for this repo"`);
- for an ignored repo: that it has no Outline folder
  (`scripts/session-start.sh::"in the worklog-persist config"`);
- otherwise: that the world is unresolved, with the resolver's `config_error`
  as the cause, or a default cause naming `WORKLOG_WORLD`
  (`scripts/session-start.sh::"config_error"`).

A resolver failure adds nothing and never fails the hook
(`scripts/session-start.sh::"a resolver failure must never break session start"`)
`[verified]`.

enforcement: `tests/test_offswitch.sh::"hook names kb_path"` and
  `tests/test_offswitch.sh::"hook states unresolved cause"` (test suite only).
  The ignored-repo sentence has no hook-level test `[verified]`.

### The hook names the server, not a tool prefix

The reminder text refers to `` `outline` `` as an MCP server name
(`scripts/session-start.sh::"durable work-state store"`), but never spells out a
`mcp__...` tool prefix `[verified]`. Resolving the live prefix
(`mcp__outline__*` or the plugin-scoped one) is left entirely to the skill in
`persistence-protocol`, one sentence and a link per
[`../CONVENTIONS.md`](../CONVENTIONS.md): see
[`../persistence-protocol/CONTRACTS.md`](../persistence-protocol/CONTRACTS.md).

enforcement: convention. Nothing in this block checks that the reminder text
  stays prefix-agnostic; a future edit could hardcode a prefix without failing
  any test owned by this block `[verified]`.

## `scripts/persistence-state.sh` interface

### Four subcommands: `path`, `status`, `off`, `on`

`scripts/persistence-state.sh::"usage: persistence-state.sh {path|status|off|on}"`
is both the usage message and the full set of valid first arguments, dispatched
by a `case` statement; any other argument exits `2` `[verified]`.

enforcement: `tests/test_offswitch.sh` exercises `status`, `off`, and `on`
  at run time. `path` is not called by any test in this repo `[verified]`;
  see [`GAPS.md`](GAPS.md).

### `status` prints exactly `on` or `off`

`scripts/persistence-state.sh::is_off()` decides; `status` echoes `off` when it
returns true, `on` otherwise `[verified]`.

enforcement: `tests/test_offswitch.sh::"default on"` and the paired
  `off`/`on` toggle checks assert the literal string.

### State path resolution: ask the resolver, never restate it

`scripts/persistence-state.sh::state_dir()` resolves `XDG_STATE_HOME`, falling
back to `$HOME/.local/state`, and appends the literal directory name
`worklog-persist` `[verified]`. `scripts/persistence-state.sh::state_file()`
appends `/off` to that directory `[verified]`. Any other document that needs the
state path cites these two functions and their precedence, never a literal path
`[verified]`, per [`../CONVENTIONS.md`](../CONVENTIONS.md).

enforcement: `tests/test_offswitch.sh` sets `XDG_STATE_HOME` to an isolated
  temp directory for the whole suite, which only works if `state_dir()` actually
  honors that variable `[verified]`.

### `WORKLOG_HOOK_OFF=1` overrides the marker file, in both directions

`scripts/persistence-state.sh::is_off()` checks
`scripts/persistence-state.sh::"WORKLOG_HOOK_OFF"` before it checks the marker
file, so the env var forces `off` even with no marker file present, and the `on`
command cannot clear it `[verified]`. The `on` command detects this and prints a
warning rather than claiming success
(`scripts/persistence-state.sh::"off-file cleared"`) `[verified]`.

enforcement: `tests/test_offswitch.sh::"env override status"` and
  `tests/test_offswitch.sh::"env override silences hook"`, run-time checks in
  the offline suite.
