---
block: persistence-protocol
doc: GAPS
verified_against: 487ab42
verified_on: 2026-09-28
---

# Gaps

Debt and unenforced boundaries in this block. Every entry here is a claim about
what does *not* check itself; the entries in [`CONTRACTS.md`](CONTRACTS.md)
carry `enforcement:` fields that say the same thing per-contract. This file
collects the pattern.

---

## The whole protocol is prompt text

`skills/worklog-persist/SKILL.md::"This skill is the operational contract"`
[verified] is a markdown file the model reads and is expected to follow; it is
not code that runs. Every rule in it, the availability check, the redact-before-
write step, the idempotent update, the verified/inferred/blocked labeling,
depends on the agent actually doing what the text says in a given session.
Nothing in this repository observes a live session and fails it for skipping a
step (`tests/test_redact.py` and `tests/test_context.sh` test the two helper
scripts in isolation, and `tests/test_structure.sh` tests that the files exist
and name the right strings; none of the three drives an actual Outline call).
Concretely, nothing stops a session from: calling `create_document` twice for
the same task slug, calling `update_document` with an unredacted secret in the
body, or reporting "saved to Outline" without ever calling a write tool. See
[`../verification/GAPS.md`](../verification/GAPS.md) for what the test suite as
a whole does and does not cover.

## No migration from the 0.2 manifest

The resolver does not look for the old YAML manifest or read the old world env
var, by design (see [`DECISIONS.md`](DECISIONS.md#its-own-config-not-a-shared-manifest)).
An operator who upgrades without writing the TOML file gets `UNRESOLVED` for
every repo, with `config_error` set to `config not found: ...` [verified]. The
SessionStart hook passes that cause on, so the agent asks, but nothing converts
the old file for them [inferred: no code in this repo reads YAML any more].

## A config with one bad entry is dropped whole

`scripts/resolve_context.py::shape_error()` rejects the whole file when any one
part has the wrong shape, for example one `projects` value that is not an array
of tables [verified]. Every repo then resolves as if no config existed. The
cause is in `config_error`, but a single typo still turns off routing for all
worlds [inferred from `load_config()` returning `None` on any shape error].

## The old-Python branch is untested

`scripts/resolve_context.py::load_config()` reports `tomllib needs Python 3.11 or newer`
when `import tomllib` fails. No test runs it under an older interpreter
[verified].

## Redaction coverage is a fixed rule list, not a guarantee

`scripts/redact.py::"defence-in-depth filter"` [verified] and
`scripts/redact.py::"do not put secrets into the record in the first place"`
[verified] both say this directly in the module's own docstring: `_RULES` is a
finite, hand-maintained list of shapes (bearer tokens, a handful of vendor key
prefixes, PEM blocks, generic `key=value`, URL passwords, IBAN, Polish NIP). A
secret in a shape not on that list passes through unredacted, and the write-
before-redact ordering in every command depends entirely on the agent
remembering to run it, per the "whole protocol is prompt text" gap above.

## Commands do not repeat the ToolSearch discovery step

None of the seven `commands/*.md` files mentions `ToolSearch` or the dual-
prefix rule; they call the tool verbs directly (`list_collections`,
`create_document`, and so on) and rely on the invoking session having already
loaded `skills/worklog-persist/SKILL.md::"Find them with ToolSearch"` [verified]
by that point. This is consistent with the design in
[`DECISIONS.md`](DECISIONS.md) (one canonical file, thin command pointers), but
it means a command run without the skill's tool-discovery text loaded first has
no fallback instruction of its own for finding the right prefix
[inferred: no code path in this repo forces the skill body to load before a
command body does].

## No test exercises the idempotency contract end to end

`tests/test_context.sh` and `tests/test_redact.py` cover
`scripts/resolve-context.sh` and `scripts/redact.py` in isolation, and
`tests/test_structure.sh::"all 7 verb commands present"` [verified] only checks
file existence. None of them, nor anything else found at this pin, drives a
`list_documents` / `create_document` / `update_document` sequence to prove the
"match on project + task slug, update instead of duplicate" rule actually holds
against a real or mocked Outline. `tests/test_live_outline.sh` exists and is
closest to this, but it is owned by [`verification`](../verification/README.md);
see that block's docs for what it actually proves.
