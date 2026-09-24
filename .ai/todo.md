# worklog-persist — build plan

Extract the Outline durable work-state persistence contract from `dotfiles-next`
and package it as a standalone Claude Code plugin `worklog-persist`.

Scope decision (user): **Option 1** — standalone plugin only. Do NOT modify the
live `dotfiles-next` repo (no install.sh edits, no golden-master regen). The
dotfiles migration is a separate reviewed follow-up.

## Migration map (source: /home/me/Development/dotfiles-next)

- **Contract (move):** `claude/skills/outline/SKILL.md`, `claude/hooks/outline.json`,
  the `outline` entry in `mcp.json`.
- **Reflection only (keep out):** `claude/agents/critic.md`, `claude/commands/reflect.md`,
  `claude/hooks/reflect_gate.py`, `kb/curriculum*.py`.
- **Graph sync only (keep out):** `graphify/sync_outline.py`, `graphify/outline-graph-sync`,
  `graphify/install-graph-hooks.sh`, `bin/outline-graph-sync.sh`, `kb/outline.py`.
- **Generated views (never hand-edit):** `codex/hooks/outline.json`, `codex/AGENTS.md`,
  `opencode/AGENTS.md` — regen `make codex-build`/`opencode-build`. Out of scope for opt 1.
- **Depends on (external, not vendored):** `kb list` / `~/.config/kb/worlds.yaml` for world
  resolution. Plugin degrades gracefully when absent; never hardcodes a world name.
- **Unchanged behavior preserved:** SessionStart rule text + dedupe marker `"Outline (MCP server"`,
  `WORKLOG_HOOK_OFF` gate, world resolution via `kb list`, no-secrets rule.

## Key doc facts (verified 2026-09-21)

- Plugin `hooks.json` wraps events in `{"hooks": {...}}`; scripts referenced via
  `${CLAUDE_PLUGIN_ROOT}`; `hooks/` at plugin root, not inside `.claude-plugin/`.
- KNOWN BUG: plugin SessionStart `additionalContext` may not surface to Claude
  (anthropics/claude-code #16538; VS Code #88086). Same hook in user settings works.
  => the SKILL (auto-activates on its description) is the robust driver; hook is best-effort.

## Behavior contract -> native mapping

7 verbs = slash commands (prompts that drive `mcp__outline__*` per the skill):
`/load /start /checkpoint /handoff /complete /dry-run /off`.
`off` also flips a persisted state file honored by the SessionStart hook.

## Tasks

- [x] Migration map + format decision + doc verification
- [ ] plugin.json + marketplace.json
- [ ] .mcp.json (reuse outline transport, env placeholders, no creds)
- [ ] hooks/hooks.json + scripts/session-start.sh (WORKLOG_HOOK_OFF + off-file gate)
- [ ] scripts/resolve-context.sh (world-agnostic; git-derived project/branch/worktree)
- [ ] scripts/redact.py (secret redaction, fixture-tested)
- [ ] scripts/persistence-state.sh (off/on toggle)
- [ ] skills/worklog-persist/SKILL.md (persistence protocol + record schema + idempotency)
- [ ] commands/{load,start,checkpoint,handoff,complete,dry-run,off}.md
- [ ] install.sh (idempotent local marketplace install + enable/disable helpers)
- [ ] tests/ (discovery, idempotent install, availability, world resolution, identity,
      load, create, idempotent checkpoint, handoff/complete, dry-run, unavailable,
      redaction, preserve foreign MCP/hooks, no duplicate docs)
- [ ] README.md
- [ ] Run: shellcheck/py tests, dry-run install, second install (idempotent)

## Review (2026-09-21)

All build tasks done. Test outcomes:
- `tests/test_redact.py` — 12 passed (RED first: 2 real gaps found — `sk-proj-` hyphen,
  keys ending `_TOKEN`; fixed, then GREEN).
- `tests/test_context.sh` — PASS (identity + world-agnostic: KB_WORLD honored, UNRESOLVED
  sentinel, remote basename, slug validation).
- `tests/test_offswitch.sh` — PASS (off/on toggle + hook gating + WORKLOG_HOOK_OFF).
- `tests/test_structure.sh` — PASS (discovery, idempotent --check, single outline MCP,
  env-only creds, wrapped hooks + marker, 7 commands).
- `install.sh --check` PASS; `--dry-run` emits correct idempotent commands (claude CLI present).
- `bash -n` clean on all shell; `py_compile` clean.

**Verified:** offline suite green; structure valid; scripts run; redaction covers named
fixtures; world resolution has no hardcoded world.
**Inferred (not run live):** actual Outline read/write lifecycle — driven by the agent via
`mcp__outline__*` per SKILL; covered by opt-in `tests/test_live_outline.sh` (reachability only,
no doc mutation) which is skipped by default.
**Unverified:** real `claude plugin install` of this marketplace (did not mutate the live CLI
registry without user go-ahead); plugin SessionStart additionalContext delivery (known upstream
bugs — SKILL is the fallback).
**Blocked/out of scope (opt 1):** dotfiles-next install.sh edits + codex/opencode golden-master
regen; deferred to a separate reviewed step.

## 2026-09-24: align with dotfiles-next structure

- [x] install.sh: dry-run default, --apply, --yes, worktree refusal, exact plugin@marketplace match (69d73de)
- [x] Makefile, pyproject.toml + uv.lock, AGENTS.md, .claude/CLAUDE.md; tests/run.sh removed (69d73de)
- [x] tests/test_install.sh: 7 cases, red on old installer, green on new (69d73de)
- [x] Skill finds Outline tools under either MCP prefix; regression test in test_structure.sh (8b3075f)
- [x] docs/ block tree: packaging, session-hook, persistence-protocol, verification (6e559c3)
- [x] tests/test_docs_layout.py: 6 checks with positive controls; docs pinned to 6e559c3 (4f96430)

### Review

Verified: `make check` green (18 pytest, 5 shell suites, install.sh --check); `make lint` clean.
Red runs seen for test_install.sh cases and the skill prefix test.
Not done: live install (`make install`) and live Outline test; the outline MCP returned HTTP 401 this session.
Observed machine state: old `outline-persist@kolezka` plugin is still installed and enabled.
