# worklog-persist

A focused Claude Code plugin that gives your sessions a **durable work-state
layer** backed by the Outline MCP server. It preserves the state of active
engineering work between agent sessions: what task is in progress, what was
verified, what changed, which decisions were made, what is blocked, and what the
next action is.

It is a persistence layer only. Graph synchronization, reflection promotion and
curriculum clustering are deliberately **not** part of this plugin.

The plugin is named `worklog-persist`, not `outline-persist`: the `outline` name
belongs to the Outline MCP server (`mcp__outline__*`) and the separate `outline`
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
./install.sh            # register local marketplace + install (idempotent)
./install.sh --check    # validate plugin structure only (no claude needed)
./install.sh --dry-run  # print the exact install commands without running them
```

Re-running `./install.sh` is safe: it skips the marketplace add and plugin install
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

./install.sh --disable                        # disable the whole plugin
./install.sh --enable
./install.sh --uninstall
```

When disabled, the SessionStart hook stops injecting the durable-memory rule and
no automatic writes happen. The manual commands still work.

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
- An undeclared repo uses `$KB_WORLD`, else the world stays `UNRESOLVED` and the
  agent asks once. A repo under `ignore:` gets no world and no folder by default.
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
bash tests/run.sh                 # full offline suite (redaction, identity, off-switch, structure)
WORKLOG_PERSIST_LIVE=1 bash tests/test_live_outline.sh   # opt-in reachability check
```

Offline tests use local fixtures and mocks; the live test is opt-in and needs no
credentials in CI.

## Scope boundary

This plugin was extracted from `dotfiles-next` as the Outline **persistence**
contract only: the `outline` skill, its SessionStart rule, and the `outline` MCP
entry. Reflection (`critic`/`reflect`), graph sync (`graphify`, `sync_outline`)
and curriculum remain separate systems and are not included here.
