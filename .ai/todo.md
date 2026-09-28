# Task: config-aware routing for worklog-persist

- [x] scripts/resolve_context.py: manifest-aware identity (world/project/kb_folder/ignore, collections, worktree canonicalisation, ticket slugs)
- [x] scripts/resolve-context.sh: thin wrapper
- [x] session-start.sh: inject resolved kb_path
- [x] SKILL.md + commands: use resolved paths, bootstrap seeding shape, status->parent flag map
- [x] tests: manifest cases, worktree, ticket slug
- [x] README, install.sh --check, version bump
- [x] run tests; independent review

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
- `tests/test_context.sh` — PASS (identity + world-agnostic: world env var honored, UNRESOLVED
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


## 2026-09-24: repo layout and docs tree

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
Observed machine state: old `outline-persist@<marketplace>` plugin is still installed and enabled.

## Review (routing)
- Suite green: `PATH=/usr/bin:$PATH bash tests/run.sh` (python3 is shimmed by a plugin in Claude sessions).
- Red run on master: test_context aborts with exit 2 on ticket slug; hook kb_path check fails.
- Independent review found 5 issues (ignored repo plus world env var, nested ignore, --separate-git-dir, malformed config crash, misleading hook cause). All fixed test-first.
- Not committed. `.claude/tdd-guard/data/modifications.json` is scratch, do not stage.

## 2026-09-28: standalone

- [x] Resolver reads the plugin's own config (`$WORKLOG_CONFIG`, else a file under `~/.config/worklog-persist/`). First pass used TOML; see the follow-up below.
- [x] World env var is now `WORKLOG_WORLD`. The old name and the old manifest are ignored, locked by the "old coupling ignored" cases in `tests/test_context.sh` (red on the 0.2 resolver, green now).
- [x] JSON keys `manifest`/`manifest_error` became `config`/`config_error`; `world_source` says `config`. The offline mirror and its output key are gone.
- [x] Hook, skill, commands, README and docs describe the plugin on its own. Dedupe-marker test and docs contract removed; the reminder text is unchanged.
- [x] Plugin version 0.3.0.

### Follow-up: YAML and onboarding

- [x] Config is YAML again (`config.yaml`), needs PyYAML; missing PyYAML is reported in `config_error`, never a crash. New output key `config_path`.
- [x] `scripts/config-add.sh` (+ `config_add.py`): `project` and `ignore` subcommands; creates the file, keeps entries, idempotent, refuses conflicts and unparseable files, atomic replace. `tests/test_config_add.sh` red then green.
- [x] Hook: unresolved repo (config missing or repo not declared) gets an onboarding instruction with cause and config path; a broken config gets "fix it first". Base reminder unchanged. Hook cases red then green.
- [x] Skill: Onboarding section (worlds read live from Outline, one question, write via the script, bootstrap, confirm). New `/setup` command; install.sh --check and test_structure now expect 8 commands.

### Merge of master (Stop guard, #6)

- [x] Kept: Stop guard (hooks.json, stop-guard.sh, stop_guard.py, test_stop_guard.sh), non-git `workspace` project, path-root tier over the one config.
- [x] Dropped: sibling `worlds*.yaml` scan and its output key. Precedence is config, `WORKLOG_WORLD`, path root, `UNRESOLVED` (onboarding).
- [x] Stop guard sends an unresolved repo to `/setup`. New tests: overlay manifest ignored, path-root repo gets no onboarding, stop reason points to `/setup`.

