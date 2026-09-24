# Task: manifest-aware routing for worklog-persist (align with dotfiles-next outline KB)

- [x] scripts/resolve_context.py: manifest-aware identity (world/project/kb_folder/ignore, collections, worktree canonicalisation, ticket slugs, mirror dir)
- [x] scripts/resolve-context.sh: thin wrapper
- [x] session-start.sh: inject resolved kb_path
- [x] SKILL.md + commands: use resolved paths, bootstrap seeding shape, status->parent flag map, mirror fallback for load
- [x] tests: manifest cases, worktree, ticket slug
- [x] README, install.sh --check, version bump
- [x] run tests; independent review

## Review
- Suite green: `PATH=/usr/bin:$PATH bash tests/run.sh` (python3 is shimmed by a plugin in Claude sessions).
- Red run on master: test_context aborts with exit 2 on ticket slug; hook kb_path check fails.
- Independent review found 5 issues (ignored+KB_WORLD, nested ignore, --separate-git-dir, malformed manifest crash, misleading hook cause). All fixed test-first.
- Not committed. `.claude/tdd-guard/data/modifications.json` is scratch, do not stage.
