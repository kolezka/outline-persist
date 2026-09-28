---
block: persistence-protocol
doc: CONTRACTS
verified_against: 487ab42
verified_on: 2026-09-28
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
[verified]. The shell file is a thin wrapper that execs
`scripts/resolve_context.py` (`scripts/resolve-context.sh::"Thin wrapper"`)
[verified]. `scripts/resolve_context.py::main()` prints one JSON object with
these keys: `repo`, `repo_root`, `project`, `world`, `world_source`,
`candidate_worlds`, `ignored`, `branch`, `worktree`, `task_slug`,
`root_collection`, `global_collection`, `archive_collection`, `kb_path`,
`tasks_path`, `record_path`, `config`, `config_error` [verified].

- `repo_root` is the main checkout, also from a linked worktree
  (`scripts/resolve_context.py::canonical_repo()`) [verified].
- `project` is the config `name` of a declared repo, else the basename of the
  `origin` remote with `.git` stripped, else the main checkout directory name
  (`scripts/resolve_context.py::"remote", "get-url", "origin"`) [verified].
- `world` comes from the config when the repo is declared there
  (`world_source` = `config`), else from `$WORKLOG_WORLD` (`env`), else it is the
  sentinel `UNRESOLVED` (`fallback`)
  (`scripts/resolve_context.py::"WORKLOG_WORLD"`) [verified]. An ignored repo
  never takes the env world [verified]. No other env var or file sets it
  [verified].
- `kb_path` is the config `kb_folder` when set, else
  `<root_collection>/<world>/<project>`, and `None` while the world is
  `UNRESOLVED` [verified]. `tasks_path` and `record_path` hang off it.
- `config` is the path that was read, or `None`; `config_error` says why no
  config was used (`not found`, `unreadable`, `malformed`), or is `None`
  (`scripts/resolve_context.py::load_config()`) [verified].
- `task_slug`, when given, must match `scripts/resolve_context.py::SLUG_RE`
  (kebab-case, optionally ticket-prefixed like `AD-163-uat-checklist`), or the
  script exits `2` with a message on stderr
  (`scripts/resolve_context.py::"invalid task slug"`) [verified].

enforcement: `tests/test_context.sh::"WORKLOG_WORLD honored"`,
`tests/test_context.sh::"config identity"`,
`tests/test_context.sh::"worktree identity"`,
`tests/test_context.sh::"ignored beats WORKLOG_WORLD"`,
`tests/test_context.sh::"old coupling ignored"` and
`tests/test_context.sh::"invalid slug rejected"` (test suite only, via
`make check`, not on every invocation of the script).

---

## Plugin config file

The resolver reads one TOML file: `$WORKLOG_CONFIG`, else
`~/.config/worklog-persist/config.toml`
(`scripts/resolve_context.py::config_path()`) [verified]. It is parsed with the
standard library `tomllib` (`scripts/resolve_context.py::"import tomllib"`), so
the plugin has no third-party runtime dependency [verified]. The shape it reads:

- `[outline]` with `root_collection`, `global_collection`, `archive_collection`.
  A missing key keeps `scripts/resolve_context.py::DEFAULT_OUTLINE` [verified].
- `[[worlds]]` with `name`, each holding `[[worlds.projects]]` with `name`,
  `repo` and an optional `kb_folder`. `repo` is matched after `~` expansion and
  symlink resolution (`scripts/resolve_context.py::expand()`) [verified].
- top-level `ignore = [...]`: a repo equal to or below one of these dirs is
  `ignored` [verified].

Any other key is ignored. A file with the wrong shape is rejected whole by
`scripts/resolve_context.py::shape_error()` and reported in `config_error`, never
raised [verified].

enforcement: `tests/test_context.sh::"malformed config"`,
`tests/test_context.sh::"unparseable config"` and
`tests/test_context.sh::"missing config reported"` (test suite only).

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

The record's identity is `project` + `task_slug`, realized as the document at
`record_path`
(`skills/worklog-persist/SKILL.md::"The record identity is"`) [verified]. Before
creating a record, the commands call `list_documents` scoped to that `Tasks`
folder and match the slug; if found, they `update_document` it instead
(`commands/start.md::"prefer updating the existing record over creating a duplicate"`)
[verified]. `commands/checkpoint.md::"idempotency key = project + task slug"`
names the same rule for the checkpoint step [verified]. A timestamp alone is explicitly
rejected as an identity source:
`skills/worklog-persist/SKILL.md::"Never use a timestamp as document identity."`
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
There is no offline read path: `/load` says persistence is unavailable and stops
(`commands/load.md::"say persistence is unavailable and stop"`) [verified].

enforcement: convention. This is prompt text interpreted by the model each
session; no script or test observes whether the agent actually checked
availability before writing.
