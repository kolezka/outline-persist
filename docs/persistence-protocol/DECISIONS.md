---
block: persistence-protocol
doc: DECISIONS
verified_against: 6e559c3
verified_on: 2026-09-24
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

`skills/worklog-persist/SKILL.md::"Never use a timestamp alone as document identity."`
[verified]. The alternative that lost: naming each checkpoint's record by when
it was written (e.g. one document per session or per day). That would break the
"same document, updated" promise in
`commands/checkpoint.md::"idempotency key = project + task slug"` [verified]:
every checkpoint would instead create a new document, and `/load` would have no
single place to read from. The key actually chosen, `project` + `task_slug`
(`skills/worklog-persist/SKILL.md::"stable key = resolved"` [verified]),
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

`scripts/resolve-context.sh::"Never hardcode a world name"` [verified] and
`skills/worklog-persist/SKILL.md::"declare different world sets"` [verified]
give the same reason from two files: a base world and an overlay world declare
different sets, so any world name written into this plugin would be correct for
at most one operator and wrong for everyone else the day it is read. The
alternative that lost: hardcoding the world this plugin happened to be built
against, which is exactly the shape `tests/test_context.sh::"KB_WORLD honored"`
[verified] exists to keep out, by proving the value actually comes from the
environment.

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
