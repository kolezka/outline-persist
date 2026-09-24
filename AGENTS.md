# Working in this repo

Rules for an agent editing `worklog-persist`. The plugin itself is described in
[`docs/README.md`](docs/README.md); this file is only about how to change it.

## Before you change anything

- Find the block that owns the file. Every tracked file is listed in exactly one
  block's `owns:` front matter under `docs/`, or in the `unassigned:` list of
  `docs/README.md`. `tests/test_docs_layout.py` fails when a file has no owner.
- Read that block's `CONTRACTS.md` and `INVARIANTS.md`. A contract keeps its shape,
  an invariant keeps its behaviour, a gap is free to fix.

## Verify

- `make check` runs every offline suite. `make lint` runs shellcheck.
- `make test` is the only correct pytest call (`env -u FORCE_COLOR uv run pytest -q`).
- Shell suites (`tests/*.sh`) are not collected by pytest. `make test-sh` runs them.
- A fix ships with a test that fails on the old code. Run it both ways.

## Install safely

- `./install.sh` is dry-run by default. Only `--apply` changes the `claude` CLI
  registry.
- Never run `make install` or `./install.sh --apply` from a linked worktree. Both
  refuse, because the registry would point at a path that dies with the branch.

## Docs

- Follow [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md): cite by `<path>::<symbol>`, never
  by line number; tag each claim with an evidence level; give each contract an
  `enforcement:` field.
- When code changes, update the owning block in the same commit and re-pin
  `verified_against` in every docs file in one pass.
- No world names and no credentials in any tracked file.
