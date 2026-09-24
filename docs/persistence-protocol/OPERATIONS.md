---
block: persistence-protocol
doc: OPERATIONS
verified_against: 8b3075f
verified_on: 2026-09-24
---

# Operations

Entry points, where identity comes from, the kill switches this block exposes
versus the one it only calls, and known stuck states.

---

## Entry points

Seven slash commands, each a thin pointer into
`skills/worklog-persist/SKILL.md::"This skill is the operational contract"`
[verified]:

| Command | Effect | Writes? |
|---|---|---|
| `/load` | `commands/load.md::"Load current work-state from Outline before starting substantive work."` | No, `commands/load.md::"Read-only. Do not write."` [verified] |
| `/start` | `commands/start.md::"Create or update the Outline task record at the start of a work item."` | Yes |
| `/checkpoint` | `commands/checkpoint.md::"Update the same Outline task record after a verified milestone."` | Yes, update only |
| `/handoff` | `commands/handoff.md::"Write a compact handoff state when the session ends, is blocked, or is transferred."` | Yes, update only |
| `/complete` | `commands/complete.md::"Record the real completion result of a work item in Outline."` | Yes, update only |
| `/dry-run` | `commands/dry-run.md::"Show the intended Outline read or write without changing anything."` | No, `commands/dry-run.md::"Output the plan only. Make no mutation to Outline."` [verified] |
| `/off` | `commands/off.md::"Disable automatic Outline persistence without removing the plugin."` | No Outline write; toggles a local switch, see below |

All descriptions above are the command's own front-matter `description:` field,
read verbatim [verified].

## Identity: what `resolve-context.sh` resolves and what it does not

Run as `scripts/resolve-context.sh [task-slug]`
(`scripts/resolve-context.sh::"Prints JSON with"`) [verified]. It resolves, in
order: `repo`/`project` from the git remote or directory name, `branch` and
`worktree` from the local checkout, `world` from `$KB_WORLD` or the
`UNRESOLVED` sentinel, and `task_slug` from its argument if valid kebab-case.
Full field-by-field contract: [`CONTRACTS.md`](CONTRACTS.md). It writes nothing
to disk; it only prints JSON to stdout. There is no cache and no local record of
a previously resolved identity, so every command re-resolves it fresh.

## Kill switches

This block owns one entry point into a kill switch it does not implement:
`/off` calls `commands/off.md::"bash ${CLAUDE_PLUGIN_ROOT}/scripts/persistence-state.sh off"`
[verified] (and `... on`, `... status`). The switch itself, the state file it
writes and where that file resolves belong to
[`session-hook`](../session-hook/README.md); see
[`session-hook/OPERATIONS.md`](../session-hook/OPERATIONS.md) for the actual
path and precedence, per the "ask the component where it writes" rule in
[`../CONVENTIONS.md`](../CONVENTIONS.md). The same command also names a second,
independent override: `commands/off.md::"WORKLOG_HOOK_OFF=1"` [verified] forces
off from the environment without touching that state file.

`/dry-run` is the closest thing to a kill switch inside this block itself: it
runs identity resolution and shows the redacted body a real write would send,
but calls no write tool
(`commands/dry-run.md::"Call NO write tool."`) [verified].

## Stuck states

- **World stuck at `UNRESOLVED`.** `scripts/resolve-context.sh` has no network
  access to a KB manifest; it only reads `$KB_WORLD`
  (`scripts/resolve-context.sh::"KB_WORLD:-UNRESOLVED"`) [verified]. If the
  session also fails to resolve it via `kb list` and does not ask the operator,
  every path it builds uses the literal string `UNRESOLVED` as a folder name.
  Recovery: set `KB_WORLD` in the environment, or answer the "ask the operator
  once" prompt (`skills/worklog-persist/SKILL.md::"ask the operator once"`)
  [verified] the next time it appears.
- **Invalid task slug.** The script exits `2` rather than guessing a
  normalization
  (`scripts/resolve-context.sh::"invalid task slug"`) [verified]. Recovery:
  supply a lowercase kebab-case slug; `/load` also lets the session
  `commands/load.md::"ask the user for the slug if unclear"` [verified].
- **Outline unavailable.** No queue, no retry, no local write path is defined
  here beyond the skill's explicit escape hatch: state it once and keep working
  without Outline
  (`skills/worklog-persist/SKILL.md::"state once that persistence is"`)
  [verified]. Recovery: nothing to do locally; the next successful availability
  check on a later command picks the work back up.
- **A duplicate record already exists** (created before a slug was made
  consistent, or by a session that skipped the `list_documents` match step).
  Nothing here detects an existing duplicate beyond matching the current slug
  exactly; recovery is a manual merge in Outline. See
  [`GAPS.md`](GAPS.md) for why no test catches this case.
