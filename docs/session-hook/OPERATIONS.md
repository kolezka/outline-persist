---
block: session-hook
doc: OPERATIONS
verified_against: 6e559c3
verified_on: 2026-09-24
---

# Operations

Entry points, state paths, kill switches, and stuck states for this block. See
[`CONTRACTS.md`](CONTRACTS.md) for the interfaces referenced here.

## Entry point

Claude Code's plugin loader runs `hooks/hooks.json`'s `SessionStart` command
(`bash ${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh`) once per session start
`[verified]`. There is no manual entry point for the hook itself; running
`bash scripts/session-start.sh` directly reproduces exactly what the hook does,
which is how `tests/test_offswitch.sh` checks it `[verified]`.

## Checking status

```
bash scripts/persistence-state.sh status
```

Prints `on` or `off` (`scripts/persistence-state.sh::is_off()`) `[verified]`. To
find the marker file itself without guessing a path:

```
bash scripts/persistence-state.sh path
```

which prints `scripts/persistence-state.sh::state_file()`'s resolved path
`[verified]`. See [`GAPS.md`](GAPS.md) for the fact that this subcommand has no
test coverage; treat its output as informational, not as something this repo's
suite protects.

## Kill switches, and which layer each one is at

Three switches turn off persistence without uninstalling anything, and they are
not the same layer:

1. **`WORKLOG_HOOK_OFF=1`** in the environment. Checked first by
   `scripts/persistence-state.sh::is_off()`; forces `off` for that shell or
   process regardless of the marker file, and cannot be cleared by the `on`
   command `[verified]`.
2. **`bash scripts/persistence-state.sh off`** (and `on` to reverse it). Writes
   or removes the marker file at `scripts/persistence-state.sh::state_file()`.
   This is what the `/off` slash command wraps
   (`persistence-protocol`, one sentence and a link:
   [`../persistence-protocol/OPERATIONS.md`](../persistence-protocol/OPERATIONS.md)).
   Only this hook's output is affected; the skill and all seven commands still
   run `[verified]`.
3. **`./install.sh --apply --disable`**, which runs `claude plugin disable` on
   the whole plugin (`packaging`, see
   [`../packaging/OPERATIONS.md`](../packaging/OPERATIONS.md)). This removes the
   hook registration itself, not just its output, and is a different mechanism
   from switch 2 `[verified]`.

Switch 2 is the one this block owns and is the right one for "stop the
reminder, keep everything else working."

## State path resolution

Never hardcode a path. Ask `scripts/persistence-state.sh::state_dir()`: it
resolves `XDG_STATE_HOME`, falling back to `$HOME/.local/state`, then appends
the literal name `worklog-persist` `[verified]`.
`scripts/persistence-state.sh::state_file()` appends `/off` to that
`[verified]`. `tests/test_offswitch.sh` points `XDG_STATE_HOME` at a temporary
directory for its whole run so it never touches a real machine's state
`[verified]`.

## Stuck states

**Status stays `off` no matter how many times `on` is run.**
Check `echo $WORKLOG_HOOK_OFF` first. `scripts/persistence-state.sh::"WORKLOG_HOOK_OFF"`
is checked before the marker file and the `on` command cannot clear an
environment variable
(`scripts/persistence-state.sh::"off-file cleared"` warns about exactly this)
`[verified]`. Unset it in the shell or process that launches Claude Code, not in
this plugin.

**Persistence came back on after upgrading from `outline-persist`.**
The old off-marker lived under a differently-named state directory that the
current `scripts/persistence-state.sh::state_dir()` never reads
(`README.md::"The off-state file does not"`) `[verified]`. Re-run
`bash scripts/persistence-state.sh off` once after the reinstall; see
[`GAPS.md`](GAPS.md).

**`off` exits with a raw `mkdir` error instead of a `worklog-persist:` message.**
The resolved state directory's parent is not writable. Fix the permissions on
the path printed by `bash scripts/persistence-state.sh path`, or set
`XDG_STATE_HOME` to a writable directory before retrying `[inferred]` from the
script's `set -euo pipefail` and its unguarded `mkdir -p` call; see
[`GAPS.md`](GAPS.md).

**Hook seems to do nothing even with status `on`.**
That may be expected: `additionalContext` delivery has known upstream gaps in
some Claude Code builds
(`scripts/session-start.sh::"anthropics/claude-code #16538"`) `[verified]`. Do
not chase this further inside this block; confirm the skill still injects the
rule on its own, since it is the primary driver
(`scripts/session-start.sh::"best-effort"`) `[verified]`.
