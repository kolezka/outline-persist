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
- 2026-09-24: zsh expands a word that starts with `=` (`echo ====` fails with "not found"). Use `---` as a separator.
- 2026-09-24: A plugin-bundled MCP server's tools are `mcp__plugin_<plugin>_<server>__*`. The bare `mcp__<server>__*` exists only when a user, project or local server with the same endpoint exists. Never hardcode one prefix in a skill; discover by ToolSearch keyword.
- 2026-09-24: The tdd-guard hook allows one new test per Write or Edit. Add tests one at a time and run each red, then green.
- 2026-09-24: The block-docs linter wants `enforcement:` at line start, with no bullet dash. A literal `path::symbol` placeholder in prose trips the citation test; write `<path>::<symbol>`.
