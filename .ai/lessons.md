# Lessons

- 2026-09-21 — Redaction regex: `sk-[A-Za-z0-9]{16,}` misses modern `sk-proj-...`
  keys (hyphen inside). Allow `-` in the class. And named-secret patterns must
  match keys that *end* in the sensitive word (`OUTLINE_API_TOKEN`), not only keys
  that equal it — drop the leading `\b`, allow `[A-Za-z0-9_]*` prefix.
- 2026-09-21 — Claude Code plugin `hooks.json` must wrap events under a top-level
  `hooks` key; user `settings.json` uses the flat shape. Plugin SessionStart
  `additionalContext` has known delivery bugs (#16538, VS Code #88086) — rely on
  the SKILL (auto-activates by description) as the robust driver, hook is best-effort.
- 2026-09-21 — Aliased `ls` in this shell buffers and returns nothing through a
  pipe; use `/bin/ls` for directory listings.
