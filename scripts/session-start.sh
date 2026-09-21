#!/usr/bin/env bash
# SessionStart hook for outline-persist.
#
# Emits the Outline durable-memory rule as SessionStart additionalContext, so a
# fresh session knows to read prior work state before acting and to checkpoint as
# it goes. Silent no-op when disabled via OUTLINE_HOOK_OFF=1 or the off-state file.
#
# NOTE: plugin SessionStart additionalContext has known delivery bugs in some
# Claude Code builds (anthropics/claude-code #16538, VS Code #88086). The
# outline-persist SKILL is the robust driver; this hook is best-effort.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if bash "$here/persistence-state.sh" status | grep -q '^off$'; then
  exit 0
fi

# Dedupe marker "Outline (MCP server" is kept verbatim for parity with the
# dotfiles-next installer, which removes duplicate SessionStart entries by it.
read -r -d '' CONTEXT <<'CTX' || true
Outline (MCP server `outline`) is this session's durable work-state store. RULE: before non-trivial work, load current task context from the project's Outline folder (do not redo captured analysis); at task start create or update the task record; checkpoint progress at meaningful verified milestones; write a handoff when the session ends or is blocked; record the real outcome at completion. Use a stable idempotency key (resolved project + task slug) so repeated checkpoints update one record, never duplicate. Never store secrets, tokens, keys or PII. If the `outline` MCP server is not connected, state that persistence is unavailable and continue. Run the outline-persist skill or /load, /start, /checkpoint, /handoff, /complete, /dry-run, /off for the full protocol.
CTX

# Emit as JSON via python to keep escaping correct.
python3 - "$CONTEXT" <<'PY'
import json, sys
ctx = sys.argv[1]
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": ctx,
    }
}))
PY
