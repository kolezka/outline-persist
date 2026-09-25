---
block: session-hook
doc: INVARIANTS
verified_against: 6e559c3
verified_on: 2026-09-24
---

# Invariants

Numbered behaviours that must hold, and the defect each one prevents. See
[`CONTRACTS.md`](CONTRACTS.md) for the interfaces these behaviours implement.

## 1. Off is OR, never AND

`scripts/persistence-state.sh::is_off()` returns true if the marker file exists
**or** `scripts/persistence-state.sh::"WORKLOG_HOOK_OFF"` is `1`; it never
requires both `[verified]`. This prevents a leftover marker file from being the
only thing keeping persistence off after an env override is removed, and
prevents an env override meant for one shell from being silently defeated by an
`on` command that only touches the file `[inferred]`.

## 2. A gate failure fails open, not closed

`scripts/session-start.sh` runs under `set -euo pipefail`, but the status check
sits inside an `if` condition
(`bash "$here/persistence-state.sh" status | grep -q '^off$'`). A nonzero exit
from that pipeline only makes the `if` false; it does not trigger `errexit`,
because commands tested by `if` are exempt from it under `set -e` `[verified]`.
So if `persistence-state.sh` ever errored before printing `on` or `off`, the
hook would fall through to emitting the reminder rather than crashing the
session start `[inferred]`. This prevents one broken shell invocation inside the
hook from blocking every new Claude Code session; the cost is that a real
failure in the state check is invisible rather than surfaced `[inferred]`.

## 3. The dedupe marker is a byte-for-byte substring, not a paraphrase

The reminder text emitted by `scripts/session-start.sh` begins with the exact
substring `scripts/session-start.sh::"Outline (MCP server"`, unchanged since the
script's own comment says an external installer matches on it
(`scripts/session-start.sh::"removes duplicate SessionStart entries by it"`)
`[verified]`. Editing the wording of the reminder without preserving this
prefix would prevent that external de-duplication from recognizing the entry,
producing a duplicate rule surfaced twice at session start `[assumption]`: the
matching logic itself is external and not re-checked from this repo.

## 4. The hook never performs an MCP call

`scripts/session-start.sh` only reads a local state file and prints text; it
contains no MCP tool invocation and no network call
(`scripts/session-start.sh::"durable work-state store"` is static text, not a
tool call) `[verified]`. This keeps the hook safe to run on every session start
regardless of whether the `outline` server is even configured; the precondition
check for that lives in the skill, not here
(see [`../persistence-protocol/INVARIANTS.md`](../persistence-protocol/INVARIANTS.md))
`[verified]`.

## 5. `state_dir()` never reads a config file, only environment and `$HOME`

`scripts/persistence-state.sh::state_dir()` resolves purely from
`scripts/persistence-state.sh::"XDG_STATE_HOME"` and `$HOME`, with no plugin
config or marketplace lookup `[verified]`. This keeps the off switch usable even
when the plugin is not correctly registered with the `claude` CLI, since it does
not depend on anything `packaging` manages `[inferred]`.
