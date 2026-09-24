---
name: start
description: Create or update the Outline task record at the start of a work item.
---

Run the worklog-persist skill's **start** step.

1. Availability check; resolve identity via `scripts/resolve-context.sh <slug>` (ask once if world is `UNRESOLVED`, the repo is `ignored`, or the slug is unclear).
2. Bootstrap if `kb_path` or its children are missing: world folder gets `INDEX` only, project folder gets `INDEX`, `Specs`, `Plans`, `Tasks`. Check each before creating it.
3. `list_documents` in `tasks_path` and match the task slug — **prefer updating the existing record over creating a duplicate** (idempotency key = project + task slug).
4. Compose the record body with: objective, acceptance criteria, repo, worktree, branch, status `active`, timestamp `Last updated: YYYY-MM-DD`, and a `## Related` section linking the Spec/Plan and related docs.
5. Pipe the body through `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/redact.py` before writing.
6. `create_document` (title `<task-slug>`, no leading H1, parent `tasks_path`) or `update_document`. Then add the record to the `Tasks` parent child-list with flag `doing`.

Never write secrets. Do not claim success unless the Outline response confirms the write.
