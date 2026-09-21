---
name: start
description: Create or update the Outline task record at the start of a work item.
---

Run the outline-persist skill's **start** step.

1. Availability check; resolve identity via `scripts/resolve-context.sh` (ask once if world unresolved or slug unclear).
2. `list_documents` in `raqz.pl/<World>/<project>/Tasks` and match the task slug — **prefer updating the existing record over creating a duplicate** (idempotency key = project + task slug).
3. Compose the record body with: objective, acceptance criteria, repo, worktree, branch, status `active`, timestamp `Last updated: YYYY-MM-DD`, and a `## Related` section linking the Spec/Plan and related docs.
4. Pipe the body through `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/redact.py` before writing.
5. `create_document` (title `<task-slug>`, no leading H1) or `update_document`. Then update the `Tasks` parent child-list with the record and its status.

Never write secrets. Do not claim success unless the Outline response confirms the write.
