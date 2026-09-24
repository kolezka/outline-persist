---
block: persistence-protocol
doc: CONTRACTS
verified_against: 8b3075f
verified_on: 2026-09-24
---

# Contracts

Durable interfaces of the skill, the commands and the two helper scripts. See
[`../CONVENTIONS.md`](../CONVENTIONS.md) for the citation and `enforcement:`
format.

---

## The skill is the single operational contract

`skills/worklog-persist/SKILL.md::"This skill is the operational contract"`
[verified]. The seven command files exist and each names its verb: `load`,
`start`, `checkpoint`, `handoff`, `complete`, `dry-run`, `off`
[verified]. Each command body says "Run the worklog-persist skill's" plus its own
step, for instance `commands/handoff.md::"Run the worklog-persist skill's"`
[verified], rather than restating the lifecycle rules, so a rule only needs to
change in `skills/worklog-persist/SKILL.md` once [inferred: one canonical file,
seven one-line pointers].

enforcement: `tests/test_structure.sh::"all 7 verb commands present"` checks
only that the seven files exist, not that their bodies still defer to the
skill (test suite only).

---

## MCP tool discovery: two possible prefixes, never assumed

The Outline tools are `list_collections`, `list_documents`, `fetch`,
`create_document`, `update_document`, `move_document`
(`skills/worklog-persist/SKILL.md::"Their prefix depends on"`)
[verified]. Their prefix is `mcp__outline__*` when a user, project or local scope
also configures an `outline` server, or
`mcp__plugin_worklog-persist_outline__*` when only the plugin's own server
definition exists, because Claude Code connects once per matching server
definition rather than exposing both
(`skills/worklog-persist/SKILL.md::"Claude Code then connects once"`)
[verified]. Which case applies depends on `.mcp.json`, owned by
[`packaging`](../packaging/CONTRACTS.md); this block only names both outcomes and
never assumes one, one sentence and a link per
[`../CONVENTIONS.md`](../CONVENTIONS.md) [inferred]. The skill instructs
discovery by keyword, not by hardcoding either string:
`skills/worklog-persist/SKILL.md::"Find them with ToolSearch"` and
`skills/worklog-persist/SKILL.md::"Never assume"` [verified]. None of
the seven `commands/*.md` files contains the literal string `mcp__`, so they
cannot hardcode the wrong one; they name only the tool verbs and defer prefix
discovery to the skill [verified].

Background on why Claude Code exposes only one prefix per logical server:
[Claude Code MCP docs](https://code.claude.com/docs/en/mcp) [assumption: external
source, not re-verified against the running product for this pin].

enforcement: `tests/test_structure.sh::"skill handles both MCP tool prefixes"`
asserts the skill text names the plugin-scoped prefix and does not hardcode a
`select:mcp__outline__` filter (test suite only; nothing checks this at agent
run time).

---

## Identity resolution: `scripts/resolve-context.sh`

Invoked as `skills/worklog-persist/SKILL.md::"bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-context.sh"`
[verified]. Prints one JSON object with exactly six fields: `repo`, `project`,
`world`, `branch`, `worktree`, `task_slug`
(`scripts/resolve-context.sh::"repo, project, world, branch, worktree, task_slug"`)
[verified].

- `project` and `repo` are the basename of `git remote get-url origin` with
  `.git` stripped, falling back to the working-tree directory name when there is
  no remote (`scripts/resolve-context.sh::"remote get-url origin"`)
  [verified].
- `world` is `$KB_WORLD` if set, else the literal sentinel `UNRESOLVED`
  (`scripts/resolve-context.sh::"KB_WORLD:-UNRESOLVED"`)
  [verified]. The script itself never shells out to `kb`; see
  [`GAPS.md`](GAPS.md) for what that means for the manifest fallback the skill
  describes.
- `task_slug`, when given, must match lowercase kebab-case
  (`scripts/resolve-context.sh::"^[a-z0-9]+(-[a-z0-9]+)*$"`) [verified], or the
  script exits `2` with a message on stderr
  (`scripts/resolve-context.sh::"invalid task slug"`) [verified].

enforcement: `tests/test_context.sh::"remote project basename"`,
`tests/test_context.sh::"KB_WORLD honored"` and
`tests/test_context.sh::"invalid slug rejected"` cover the three branches
above (test suite only, run via `bash tests/test_context.sh` / `make check`,
not on every invocation of the script itself).

---

## Secret redaction: `scripts/redact.py`

A stdin-or-file-args-to-stdout filter: `redact(text: str) -> str` applies an
ordered list of regex rules and returns the rewritten text
(`scripts/redact.py::redact()`) [verified]. Rules live in
`scripts/redact.py::_RULES` and run in order so a specific pattern (a GitHub
token, an IBAN) wins over the generic `key=value` catch-all
(`scripts/redact.py::"structured/longer"`) [verified]. Every match becomes
`<REDACTED:kind>`, for example `<REDACTED:api-key>`, `<REDACTED:private-key>`,
`<REDACTED:nip>` (`scripts/redact.py::"<REDACTED:kind>"`) [verified]. `main()`
reads args-as-files or stdin and writes to stdout
(`scripts/redact.py::main()`) [verified].

The skill requires every candidate record body to pass through this filter
before any write:
`skills/worklog-persist/SKILL.md::"Pipe every candidate record body through"`
[verified]. All five write-capable commands repeat the instruction, for example
`commands/start.md::"Pipe the body through"` [verified] and
`commands/checkpoint.md::"Redact via"` [verified].

enforcement: `tests/test_redact.py::test_generic_named_secret()`,
`tests/test_redact.py::test_private_key_block()` and
`tests/test_redact.py::test_url_password()` exercise `redact()` in isolation
(unit test, in the test suite only). Nothing enforces that an agent session
actually pipes a given write through `redact.py` before calling
`create_document` or `update_document`; that step is prompt text only, see
[`GAPS.md`](GAPS.md).

---

## Persisted record identity: idempotency key

The record's identity is `project` + `task_slug`, realized as the document
`Tasks/<task-slug>` inside `raqz.pl/<World>/<project>`
(`skills/worklog-persist/SKILL.md::"stable key = resolved"`) [verified]. Before
creating a record, the commands call `list_documents` scoped to that `Tasks`
folder and match the slug; if found, they `update_document` it instead
(`commands/start.md::"prefer updating the existing record over creating a duplicate"`)
[verified]. `commands/checkpoint.md::"idempotency key = project + task slug"`
names the same rule for the checkpoint step [verified]. A timestamp alone is explicitly
rejected as an identity source:
`skills/worklog-persist/SKILL.md::"Never use a timestamp alone as document identity."`
[verified].

enforcement: convention. No test drives a real or mocked `list_documents` /
`create_document` round trip against this rule; `tests/test_redact.py` and
`tests/test_context.sh` cover the two helper scripts, not the Outline calls
the skill text describes. See [`../verification/README.md`](../verification/README.md)
for what the test suite as a whole proves.

---

## Availability precondition

Every command opens with an availability check before any read or write:
`skills/worklog-persist/SKILL.md::"confirm the server is connected"` [verified],
and each command file repeats it, e.g.
`commands/load.md::"MCP server is available"` [verified]. On failure, the rule is
to say so once and continue the task without Outline, never to substitute a
local claim of success:
`skills/worklog-persist/SKILL.md::"state once that persistence is"` [verified].

enforcement: convention. This is prompt text interpreted by the model each
session; no script or test observes whether the agent actually checked
availability before writing.
