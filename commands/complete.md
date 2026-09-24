---
name: complete
description: Record the real completion result of a work item in Outline.
---

Run the worklog-persist skill's **complete** step.

1. Availability check; resolve identity; locate the existing record at `record_path`.
2. Record the actual outcome: the verification commands run and their decoded outcomes, links to the merged commit/PR/pipeline. Set status `complete`, refresh `Last updated:`.
3. **Do not mark complete merely because files changed.** Only claim completion for acceptance criteria that were verified; list any that were not.
4. Use strikethrough + date for closed items; do not delete history. Redact via `scripts/redact.py`; `update_document` the same record; update the `Tasks` parent to `done`.

Confirm from the Outline response before reporting completion.
