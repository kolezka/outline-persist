---
name: load
description: Load current work-state from Outline before starting substantive work.
---

Run the worklog-persist skill's **load** step.

1. Confirm the `outline` MCP server is available (`list_collections`). If not, say persistence is unavailable and stop.
2. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-context.sh` to get repo, project, world, branch, worktree. If `world` is `UNRESOLVED`, resolve via `kb list` or ask once.
3. `list_documents` scoped to `raqz.pl/<World>/<project>/Tasks`; find the record for the current task slug (ask the user for the slug if unclear).
4. `fetch` that record plus the project `INDEX.md` and any linked Specs/Plans.
5. Return a concise current-state summary: objective, status, verified facts, decisions, blockers, next action. Do not restate the whole document.

Read-only. Do not write.
