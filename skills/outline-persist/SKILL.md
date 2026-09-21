---
name: outline-persist
description: Use whenever you start, checkpoint, hand off, or finish non-trivial work, or need prior context on a task/feature/bug/decision. Durable work-state persistence backed by the Outline MCP server — read current state before acting, record task start, checkpoint at verified milestones, write handoff and completion.
version: 0.1.0
---

# Outline work-state persistence

Outline is durable; conversation context is volatile. The state of active
engineering work lives in Outline so it survives across sessions: what task is in
progress, what was verified, what changed, which decisions were made, what is
blocked, and what the next action is.

This skill is the operational contract. The seven slash commands
(`/load`, `/start`, `/checkpoint`, `/handoff`, `/complete`, `/dry-run`, `/off`)
are thin entry points that run the relevant part of this contract.

The MCP server is registered as `outline`; its tools are `mcp__outline__*`
(`list_collections`, `list_documents`, `fetch`, `create_document`,
`update_document`, `move_document`). They may be deferred — load schemas with
ToolSearch first (`select:mcp__outline__list_collections,mcp__outline__list_documents,mcp__outline__create_document,mcp__outline__update_document,mcp__outline__fetch`).

Helper scripts live under `${CLAUDE_PLUGIN_ROOT}/scripts/`:
`resolve-context.sh` (identity), `redact.py` (secret redaction),
`persistence-state.sh` (the off switch).

## Precondition: is Outline available?

Before any read or write, confirm the server is connected: attempt
`list_collections`. If it errors as unavailable, **state once that persistence is
unavailable and continue the task without Outline** — never block work, never
substitute a local success claim for a failed remote write. A local pending
record is allowed only if this repository already has a supported local fallback;
mark it explicitly as `pending, unsynchronized`.

## Never persist secrets

Never write secrets, tokens, API keys, passwords, private keys, cookies, customer
PII, NIPs or account numbers to Outline. Pipe every candidate record body through
`python3 ${CLAUDE_PLUGIN_ROOT}/scripts/redact.py` before `create_document` /
`update_document`; it replaces secret-shaped values with `<REDACTED:kind>`. If the
user pastes a secret, redact it and warn inline. Do not log authorization headers
or raw MCP payloads.

## Identity and world resolution

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-context.sh [task-slug]`. It returns
JSON: `repo`, `project`, `world`, `branch`, `worktree`, `task_slug`.

- **Project** = basename of `git remote get-url origin` (sans `.git`), else the
  repo directory name.
- **World** is never hardcoded. It comes from `$KB_WORLD`, else the manifest via
  `kb list` (`~/.config/kb/worlds.yaml`, `KB_MANIFEST` override). If the script
  reports `world: UNRESOLVED` and `kb` cannot resolve it, ask the operator once,
  then proceed. A base world and an overlay world declare different world sets, so
  a list written into this file would be wrong for somebody the day it is written.
- **Task slug** is stable kebab-case, shared across Specs/Plans/Tasks.

## Structure and routing

Active KB collection `raqz.pl`: worlds are top-level folders, a project is
`raqz.pl/<World>/<project>`. Inside a project: `INDEX.md` plus `Specs`, `Plans`,
`Tasks` parents. Work records for a task live at `Tasks/<task-slug>` (ticket-backed:
`Tasks/<TICKET-ID>-<slug>`). Cross-project agent behaviour, conventions and lessons
go to the existing `Claude's Notebook` collection — never recreate it, never create
a second global KB. Do not write to `Archive` unless existing routing requires it.

Prefer updating an existing project document over creating a duplicate. Document
bodies must not begin with an H1 (the title is a separate field).

## The persisted work record

Persist structured state, not a transcript. Minimum fields:

- repository identity; project and world; branch and worktree;
- task slug; objective; acceptance criteria;
- status: one of `active`, `blocked`, `handoff`, `complete`;
- verified facts and evidence; inferred or unverified items; decisions;
- changed files; test and verification results; blockers; next action;
- related Outline documents; timestamp (`Last updated: YYYY-MM-DD`).

Distinguish **verified / inferred / unverified / blocked** claims explicitly — never
present an unverified claim as verified.

## Idempotency

The record identity is a stable key = resolved `project` + `task_slug`, realised as
the document `Tasks/<task-slug>` in `raqz.pl/<World>/<project>`. Before creating,
`list_documents` scoped to that `Tasks` folder and match the slug; if it exists,
`update_document` it. Repeating a checkpoint updates the same record — it must never
duplicate. Never use a timestamp alone as document identity.

## Lifecycle (maps to the commands)

- **load** — resolve identity; find the existing `Tasks/<slug>` record; read it plus
  the project `INDEX.md` and related docs before substantive work; return a concise
  current-state summary.
- **start** — create or update `Tasks/<slug>` with objective, acceptance criteria,
  repo, worktree, branch; link related Specs/Plans/existing docs. Update the `Tasks`
  parent child-list.
- **checkpoint** — after a meaningful *verified* milestone, `update_document` the same
  record: changed files, evidence, tests, decisions, blockers, next action, new
  timestamp. Never a new doc.
- **handoff** — write a compact handoff state when the session ends, is blocked or is
  transferred; status `handoff` or `blocked`; label verified / inferred / unverified /
  blocked.
- **complete** — record the real completion result with verification commands and
  their outcomes; status `complete`; strikethrough closed items, do not delete. Do not
  mark complete merely because files changed.
- **dry-run** — show the intended read or write (target collection/folder/doc, the
  fields, the redacted body) without calling any write tool.
- **off** — `bash ${CLAUDE_PLUGIN_ROOT}/scripts/persistence-state.sh off` disables the
  automatic SessionStart rule without removing the plugin; `... on` re-enables.

## When to write vs. not

Write at task start, meaningful verified checkpoints, decisions, blockers, handoff and
completion — **not on every tool call**. Don't write trivia obvious from code, or
duplicate existing content (update instead).

## Cross-linking

No orphan docs. Every record links its Plan/Spec where they exist; every doc it
depends on gets a back-link. Add a `## Related` section with `[[doc-title]]` links.
Update the `Tasks` parent every time a record is created, renamed, status-changed or
closed. Never expose `raqz.pl` / `outline.raqz.link` links in public artifacts,
commits or external messages.
