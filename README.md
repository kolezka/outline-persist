# worklog-persist

A focused Claude Code plugin that gives your sessions a **durable work-state
layer** backed by the Outline MCP server. It preserves the state of active
engineering work between agent sessions: what task is in progress, what was
verified, what changed, which decisions were made, what is blocked, and what the
next action is.

It is a persistence layer only. Graph synchronization, reflection promotion and
curriculum clustering are deliberately **not** part of this plugin.

The plugin is named `worklog-persist`, not `outline-persist`: the `outline` name
belongs to the Outline MCP server and the separate `outline`
KB skill, and a plugin with the same name shadows them. Only the plugin identity
changed. The MCP server entry, `OUTLINE_API_TOKEN` and the Outline document
routing are untouched.

## What it does

- Reads current work context from Outline before non-trivial work.
- Records task start, verified checkpoints, handoff and completion.
- Keeps one record per work item (idempotency key = resolved project + task slug),
  so repeated checkpoints update rather than duplicate.
- Redacts secret-shaped values before anything is written.
- Never claims a write succeeded unless Outline confirms it; states plainly when
  Outline is unavailable and continues.

## Install

Requires the `claude` CLI and an `outline` MCP server reachable via the standard
transport (`https://outline.raqz.link/mcp`, Cloudflare Access + Bearer token, all
from environment variables — no credentials are stored in this repo).

```bash
make                         # every target, with a one-line description each
./install.sh                 # dry-run by default: prints the plan, touches nothing
./install.sh --apply         # execute, confirming each step
./install.sh --apply --yes   # non-interactive
./install.sh --check         # validate plugin structure only (no claude needed)

make plan                    # == ./install.sh
make install                 # == ./install.sh --apply, and REFUSES from a worktree
```

`--apply` refuses to run from a linked git worktree. `marketplace add` records the
checkout path, and a worktree path is deleted with its branch.

Re-running `./install.sh --apply` is safe: it skips the marketplace add and plugin install
if they are already present, and never edits your `settings.json` or a shared
`mcp.json` — the `claude` CLI manages its own registry, so unrelated marketplaces,
plugins, MCP servers and hooks are left untouched.

## Renamed from `outline-persist`

| Old | New |
|-----|-----|
| plugin and skill `outline-persist` | `worklog-persist` |
| marketplace `outline-persist-marketplace` | `worklog-persist-marketplace` |
| env `OUTLINE_HOOK_OFF` | `WORKLOG_HOOK_OFF` |
| env `OUTLINE_PERSIST_LIVE` | `WORKLOG_PERSIST_LIVE` |
| state dir `~/.local/state/outline-persist` | `~/.local/state/worklog-persist` |

Uninstall the old plugin before installing this one:
`claude plugin uninstall outline-persist@<marketplace>`. The off-state file does not
migrate. If automatic persistence was disabled, run
`bash scripts/persistence-state.sh off` once after the reinstall.

## Enable / disable

The plugin can be disabled without uninstalling it:

```bash
/off                                         # inside a session (slash command)
bash scripts/persistence-state.sh off        # or from a shell
bash scripts/persistence-state.sh on         # re-enable
WORKLOG_HOOK_OFF=1                            # env override forces off

./install.sh --apply --disable                # disable the whole plugin
./install.sh --apply --enable
./install.sh --apply --uninstall
```

When disabled, the SessionStart hook stops injecting the durable-memory rule, the
Stop hook stops blocking unpersisted turns, and no automatic writes happen. The
manual commands still work.

## Commands

Seven slash commands map to the persistence lifecycle:

| Command       | Purpose |
|---------------|---------|
| `/load`       | Load current work-state before substantive work (read-only). |
| `/start`      | Create or update the task record with objective + acceptance criteria. |
| `/checkpoint` | Update the same record after a verified milestone. |
| `/handoff`    | Write a compact handoff state when a session ends or is blocked. |
| `/complete`   | Record the real completion result with verification outcomes. |
| `/dry-run`    | Show the intended read/write (with redaction visible), change nothing. |
| `/off`        | Disable automatic persistence without removing the plugin. |

The full operational contract lives in `skills/worklog-persist/SKILL.md`, which
also auto-activates by description — the robust driver even where the SessionStart
hook's context injection is affected by known Claude Code bugs
([#16538](https://github.com/anthropics/claude-code/issues/16538),
[#88086](https://github.com/anthropics/claude-code/issues/88086)).

## Persisted record schema

Structured state, not a transcript. Minimum fields: repository identity; project
and world; branch and worktree; task slug; objective; acceptance criteria; status
(`active` / `blocked` / `handoff` / `complete`); verified facts and evidence;
inferred/unverified items; decisions; changed files; test and verification
results; blockers; next action; related documents; `Last updated: YYYY-MM-DD`.

## KB structure and routing

The plugin follows the Outline KB layout that the `kb` tooling and the `outline`
skill in dotfiles-next use. It reads the same manifest: `$KB_MANIFEST`, else
`~/.config/kb/worlds.yaml`.

- Collections (`root_collection`, `global_collection`, `archive_collection`) come
  from the manifest `outline:` block.
- A repo declared under `worlds[].projects[]` gets its world, project name and
  optional `kb_folder` from the manifest. A linked git worktree resolves to its
  main checkout first, so it maps to the same project.
- An undeclared repo can still match an exact declaration in another
  `worlds*.yaml` sibling of the active manifest's directory; failing that it uses
  `$KB_WORLD`, then path root (the declared world whose own repos are the deepest
  ancestor-or-equal of this one; a tie between two different worlds is left
  unresolved, never guessed); otherwise the world stays `UNRESOLVED` and the agent
  asks once. This makes resolution depend on the repo's own location, not on
  which manifest happened to be active when the session started. A repo under
  `ignore:` gets no world and no folder by default.
- Records live at `<kb_path>/Tasks/<task-slug>`, where `kb_path` is `kb_folder` or
  `<root_collection>/<World>/<project>`. Ticket slugs (`AD-163-uat-checklist`)
  are accepted.
- Bootstrap follows `kb reconcile`: a world folder gets `INDEX` only, a project
  folder gets `INDEX`, `Specs`, `Plans`, `Tasks`. It is idempotent.
- `/load` can read the local mirror (`$OUTLINE_ROOT/outline-sync/<World>/<project>`)
  when the MCP server is down. The result is labelled as a possibly stale snapshot.

Check what a repo resolves to:

```bash
bash scripts/resolve-context.sh my-task-slug
```

Reading the manifest needs PyYAML. Without it the resolver reports
`manifest_error` and falls back to `$KB_WORLD`.

## Tests

```bash
make check    # everything offline: pytest suite, shell suites, structure check
make lint     # shellcheck at warning severity
make live     # opt-in reachability check against the Outline server in .mcp.json
```

Offline tests use local fixtures and mocks; the live test is opt-in and needs no
credentials in CI.

## Documentation

`docs/` describes the plugin by building block, using the same layout as
`dotfiles-next`: each block has `README`, `CONTRACTS`, `INVARIANTS`, `GAPS` and
`OPERATIONS` pages. Start at [`docs/README.md`](docs/README.md). Rules for writing
there are in [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md), and
`tests/test_docs_layout.py` enforces them.

## Scope boundary

This plugin was extracted from `dotfiles-next` as the Outline **persistence**
contract only: the `outline` skill, its SessionStart rule, and the `outline` MCP
entry. Reflection (`critic`/`reflect`), graph sync (`graphify`, `sync_outline`)
and curriculum remain separate systems and are not included here.
