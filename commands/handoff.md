---
name: handoff
description: Write a compact handoff state when the session ends, is blocked, or is transferred.
---

Run the worklog-persist skill's **handoff** step.

1. Availability check; resolve identity; locate the existing `Tasks/<slug>` record (update it, do not duplicate).
2. Write a compact handoff block: current status (`handoff` or `blocked`), what is done, what remains, the exact next action, and open questions.
3. Clearly separate **verified**, **inferred**, **unverified** and **blocked** claims so the next session can trust the record.
4. Redact via `scripts/redact.py`; `update_document`; refresh `Last updated:`; update the `Tasks` parent status flag.

Report the write only after the Outline response confirms it.
