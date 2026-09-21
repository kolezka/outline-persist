---
name: checkpoint
description: Update the same Outline task record after a verified milestone.
---

Run the outline-persist skill's **checkpoint** step.

1. Availability check; resolve identity; locate the existing `Tasks/<slug>` record. If none exists, run **start** first — never create a second record for the same work item.
2. Append/update: changed files, evidence, tests and their outcomes, decisions, blockers, next action. Refresh `Last updated:`. Keep status `active` (or set `blocked` with the blocker).
3. Label each claim **verified / inferred / unverified / blocked**. Only record a milestone that was actually verified.
4. Redact via `scripts/redact.py`, then `update_document` the SAME document (idempotency key = project + task slug). Never `create_document` here.

Confirm the update from the Outline response before reporting success.
