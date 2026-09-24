---
block: persistence-protocol
doc: INVARIANTS
verified_against: 8b3075f
verified_on: 2026-09-24
---

# Invariants

Numbered behaviours the protocol text requires, and what breaks if a session
does not follow them. None of these are enforced at agent run time; see
[`GAPS.md`](GAPS.md) for what that means in practice.

---

### 1. Never write a secret into a persisted record

`skills/worklog-persist/SKILL.md::"Never persist secrets"` [verified]. Every
write-capable command routes the body through `scripts/redact.py::redact()`
first, e.g. `commands/start.md::"Pipe the body through"` [verified]. Defect
prevented: a durable, shared wiki record permanently holding a live API key,
password or PII, which is worse than a leak in a transcript because Outline is
built to be found and reused later [inferred: the skill's own framing of
Outline as durable makes an unredacted secret durable too].

### 2. Confirm availability before any read or write

`skills/worklog-persist/SKILL.md::"confirm the server is connected"` [verified].
Defect prevented: silently skipping the read/write step and letting the agent
proceed on stale or absent context without saying so, or worse, treating a
failed remote call as if it had succeeded.

### 3. Never claim a write succeeded without a confirming response

`commands/start.md::"Do not claim success unless the Outline response confirms the write."`
[verified], repeated for handoff as
`commands/handoff.md::"Report the write only after the Outline response confirms it."`
[verified]. Defect prevented: the next session trusting a record that was never
actually written, because the current session reported success from having
sent the call, not from Outline's response.

### 4. One record per (project, task slug), never a second one

`skills/worklog-persist/SKILL.md::"stable key = resolved"` [verified];
`commands/checkpoint.md::"idempotency key = project + task slug"` [verified].
Defect prevented: two documents for the same task drifting apart, so `/load` in
a later session reads a stale or partial one depending on which it happens to
find.

### 5. A task slug is validated kebab-case or the script fails loud

`scripts/resolve-context.sh::"^[a-z0-9]+(-[a-z0-9]+)*$"` [verified]; on mismatch
the script exits `2` rather than returning a malformed slug
(`scripts/resolve-context.sh::"invalid task slug"`) [verified]. Defect
prevented: a slug like `My Task` or `Fix_Bug` silently becoming part of the
idempotency key in invariant 4, so two spellings of the same task each get
their own document.

### 6. World is read from `$KB_WORLD` or an explicit sentinel, never hardcoded

`scripts/resolve-context.sh::"KB_WORLD:-UNRESOLVED"` [verified]. Defect
prevented: the plugin's identity-resolution code naming one customer's or one
operator's world, which would make every other world's session either write to
the wrong place or silently do nothing there. `tests/test_context.sh::"KB_WORLD honored"`
exercises the override path (test suite only) [verified].

### 7. Redaction does not rewrite text that was never secret-shaped

`tests/test_redact.py::test_preserves_ordinary_text()` [verified]. Defect
prevented: `redact()` over-matching and corrupting an ordinary record body
(branch names, file paths, prose), which would make the persisted record less
trustworthy than the one it replaced.

### 8. Redaction is idempotent

`tests/test_redact.py::test_idempotent()` [verified]. Defect prevented: running
the filter twice (for instance once in `/checkpoint` and again if a caller
pipes an already-redacted body through it a second time) producing a
double-redacted, harder-to-read artifact such as nested `<REDACTED:` markers.

### 9. Completion is not claimed from file changes alone

`commands/complete.md::"Do not mark complete merely because files changed."`
[verified]. Defect prevented: a task marked `complete` in Outline while its
acceptance criteria were never actually verified, which a later session would
trust at face value per invariant 3's own logic.
