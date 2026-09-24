---
block: persistence-protocol
doc: GAPS
verified_against: 8b3075f
verified_on: 2026-09-24
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

## `resolve-context.sh` does not call `kb`

The skill describes world resolution as a fallback chain: `$KB_WORLD`,
`skills/worklog-persist/SKILL.md::"else the manifest via"` `kb list`
[verified]. The script itself only implements the first step:
`world="${KB_WORLD:-UNRESOLVED}"`
(`scripts/resolve-context.sh::"KB_WORLD:-UNRESOLVED"`) [verified], and its own
header comment says why: `kb list` renders a human table, not JSON, so the
script does not parse it
(`scripts/resolve-context.sh::"do not parse it here."`) [verified]. The `kb
list` / manifest fallback is therefore something the *agent* is expected to run
separately, as a second command, when it sees the `UNRESOLVED` sentinel. If a
session does not do that and does not ask the operator either, `UNRESOLVED`
becomes the literal folder name used in Outline paths, silently, since the
script has no way to detect that the fallback was skipped [inferred: the script
returns a plain string field with no flag distinguishing "resolved from
KB_WORLD" from "sentinel because no one has resolved it yet"].

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
