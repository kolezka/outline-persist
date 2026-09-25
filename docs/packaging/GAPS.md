---
block: packaging
doc: GAPS
verified_against: 6e559c3
verified_on: 2026-09-24
---

# Gaps

Debt and unenforced boundaries in this block. A change here is free to close
any of these without touching a contract or an invariant.

## The Outline URL is hardcoded

`.mcp.json` points at one fixed endpoint,
`` `.mcp.json::"https://outline.raqz.link/mcp"` `` [verified]. There is no
`${OUTLINE_URL}`-style placeholder and no per-user override file shipped by
this repo. A person who wants this plugin against a different Outline
instance has to fork the file or maintain a local edit that `git` will flag as
a diff on every pull. Claude Code itself supports layered `.mcp.json` scoping
(user, project, local) in general, so a workaround likely exists at that
layer, but this repo does not document or ship one, and that claim is not
re-checked against Claude Code's current behaviour in this session
[assumption].

## Whether an installed plugin is a live path or a cached copy is unverified

`claude plugin marketplace add` registers `$ROOT` as a path
(`` `install.sh::require_main_checkout()` `` depends on that fact) [verified],
but nothing in this repo's code or tests shows whether `claude plugin install`
then reads the plugin's files from that path live on every session, or copies
them into a cache at install time. If it caches, editing a tracked file after
installing requires an explicit reinstall or update before the change takes
effect; if it reads live, it does not. `AGENTS.md`'s installer guidance
(`` `AGENTS.md::"linked worktree"` ``) is consistent with either model and does
not resolve it [assumption].

## `check_structure()` is not run before `--apply`

A plain `./install.sh --apply` (or `--apply --yes`) does not call
`` `install.sh::check_structure()` `` first; only `--check` and, through it,
`make check` do [verified]. A broken plugin tree (a missing command file, a
malformed `.mcp.json`) can be installed via `claude plugin install` without
this repo's own validator ever running against it.

## `plugin_present()` / `marketplace_present()` use unanchored substring match

Both use `grep -q` on free-text CLI output without `^`/`$` anchors
(`` `install.sh::marketplace_present()` ``, `` `install.sh::plugin_present()` ``)
[verified]. A hypothetical entry that contains `${PLUGIN}@${MARKET}` as a
substring of a longer name would false-positive as "already installed". No
test constructs such a name, so this is unexercised rather than proven safe
[inferred].

## No `make` target for enable, disable or uninstall

The `Makefile` exposes `plan` and `install` but not `--enable`, `--disable`
or `--uninstall`; those are reachable only by calling `install.sh` directly,
as documented in the top-level `README.md`
(`` `README.md::"install.sh --apply --uninstall"` ``) [verified]. Minor
discoverability gap for someone who only ever runs `make`.

## `uv.lock` freshness is not checked by any target

No `Makefile` target runs `uv lock --check` or equivalent. If
`pyproject.toml`'s dependencies changed without re-running `uv lock`, `make
test` and `make check` would still resolve against a stale lock file and
nothing would fail loudly [inferred from reading every `Makefile` target and
finding no such check].
