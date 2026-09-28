---
block: persistence-protocol
doc: DECISIONS
verified_against: 487ab42
verified_on: 2026-09-28
---

# Decisions

Why this block is shaped this way, and what it deliberately gave up.

---

## The skill holds the contract; commands are one-line pointers

`skills/worklog-persist/SKILL.md::"This skill is the operational contract"`
[verified], and every command body's first line is
"Run the worklog-persist skill's **\<verb\>** step"
(`commands/handoff.md::"Run the worklog-persist skill's"`) [verified] rather
than a restatement of the lifecycle rules. The alternative that lost: writing
the full read/redact/idempotency/labeling logic into each of the seven command
files (or into the SessionStart hook, which instead only reminds the agent of
the rule per [`../session-hook/README.md`](../session-hook/README.md)). That
would mean seven, or eight, near-duplicate copies of the same rules drifting
apart the first time one of them needed a fix
[inferred: the one-file-plus-pointers shape only makes sense as a defense
against that drift; no comment in the source names the rejected alternative
directly].

## A stable key, never a timestamp

`skills/worklog-persist/SKILL.md::"Never use a timestamp as document identity."`
[verified]. The alternative that lost: naming each checkpoint's record by when
it was written (e.g. one document per session or per day). That would break the
"same document, updated" promise in
`commands/checkpoint.md::"idempotency key = project + task slug"` [verified]:
every checkpoint would instead create a new document, and `/load` would have no
single place to read from. The key actually chosen, `project` + `task_slug`
(`skills/worklog-persist/SKILL.md::"The record identity is"` [verified]),
survives renames of nothing but the task itself.

## Redaction is a filter, not a substitute for the rule

`scripts/redact.py::"defence-in-depth filter"` [verified] and
`scripts/redact.py::"do not put secrets into the record in the first place"`
[verified] both appear in the module's own docstring. The alternative that
lost: relying only on the skill's prose instruction
(`skills/worklog-persist/SKILL.md::"Never persist secrets"` [verified]) and
trusting the agent never to compose a secret into a body in the first place.
The recorded reasoning keeps both: the prose rule stays the primary control,
and `scripts/redact.py::redact()` is a mechanical backstop for the cases where the
primary rule is followed imperfectly, at the cost of being only as good as its
fixed pattern list (see [`GAPS.md`](GAPS.md)).

## World is resolved, never named

`scripts/resolve_context.py::"No world name is"` [verified] and
`skills/worklog-persist/SKILL.md::"is never hardcoded"` [verified] say the same
thing from two files. Two operators declare different worlds, so any world name
written into this plugin would be right for at most one of them [inferred]. The
alternative that lost: hardcoding the world this plugin happened to be built
against, which is exactly the shape `tests/test_context.sh::"WORKLOG_WORLD honored"`
[verified] exists to keep out, by proving the value actually comes from the
environment.

## Its own config, not a shared manifest

[historical: 2026-09-28, this change] Up to 0.2 the resolver read a YAML
manifest owned by a separate KB tool, plus that tool's world env var, and
offered a local read-only mirror written by the same tool. 0.3 cuts all of it.
The plugin now reads only its own TOML file
(`scripts/resolve_context.py::config_path()`) and `$WORKLOG_WORLD` [verified].
Why: a shared file couples two release cycles, and the old path needed a
third-party YAML parser, while `tomllib` ships with Python 3.11, which
`pyproject.toml` already requires [verified]. The alternatives that lost:
reading both files with the old one as a fallback (two sources of truth for the
same world), and keeping the old env var as an alias (a stale shell export
would keep routing records with no visible cause). The cost: an operator
upgrading from 0.2 has to write the TOML file by hand, and until then every repo
resolves to `UNRESOLVED` with `config_error` set. `tests/test_context.sh::"old coupling ignored"`
[verified] keeps the old names from quietly coming back.

## No offline mirror

The mirror was a snapshot written by another tool, so `/load` could report
stale state as current. With the cut above there is no writer for it in this
plugin. `/load` now says persistence is unavailable and stops
(`commands/load.md::"say persistence is unavailable and stop"`) [verified].

## Two MCP tool prefixes, neither one pinned

[historical: 2026-09-24, commit `8b3075f`] The skill used to hardcode
`mcp__outline__*`. On a machine where only this plugin's own `.mcp.json`
defines the `outline` server, Claude Code exposes the tools as
`mcp__plugin_worklog-persist_outline__*` instead, and the old skill text found
nothing under the name it searched for, so the agent reported Outline as
unavailable when it was actually just unnamed correctly. The fix, still current
at this pin, names both prefixes and finds the live one by keyword
(`skills/worklog-persist/SKILL.md::"Find them with ToolSearch"` [verified]),
locked in by
`tests/test_structure.sh::"skill handles both MCP tool prefixes"` [verified].
The alternative that lost: keeping a single hardcoded prefix and requiring
every installation to also register a user- or project-scope `outline` server
just so the old string would resolve.
