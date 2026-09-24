#!/usr/bin/env bash
# SessionStart hook for worklog-persist.
#
# Emits the Outline durable-memory rule as SessionStart additionalContext, so a
# fresh session knows to read prior work state before acting and to checkpoint as
# it goes. Silent no-op when disabled via WORKLOG_HOOK_OFF=1 or the off-state file.
#
# NOTE: plugin SessionStart additionalContext has known delivery bugs in some
# Claude Code builds (anthropics/claude-code #16538, VS Code #88086). The
# worklog-persist SKILL is the robust driver; this hook is best-effort.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if bash "$here/persistence-state.sh" status | grep -q '^off$'; then
  exit 0
fi

# Dedupe marker "Outline (MCP server" is kept verbatim for parity with the
# dotfiles-next installer, which removes duplicate SessionStart entries by it.
read -r -d '' CONTEXT <<'CTX' || true
Outline (MCP server `outline`) is this session's durable work-state store. RULE: before non-trivial work, load current task context from the project's Outline folder (do not redo captured analysis); at task start create or update the task record; checkpoint progress at meaningful verified milestones; write a handoff when the session ends or is blocked; record the real outcome at completion. Use a stable idempotency key (resolved project + task slug) so repeated checkpoints update one record, never duplicate. Never store secrets, tokens, keys or PII. If the `outline` MCP server is not connected, state that persistence is unavailable and continue. Run the worklog-persist skill or /load, /start, /checkpoint, /handoff, /complete, /dry-run, /off for the full protocol.
CTX

# Best-effort: a resolver failure must never break session start.
IDENTITY="$(bash "$here/resolve-context.sh" 2>/dev/null || true)"

# Emit as JSON via python to keep escaping correct.
python3 - "$CONTEXT" "$IDENTITY" <<'PY'
import json, sys
ctx, identity = sys.argv[1], sys.argv[2]
try:
    i = json.loads(identity)
except ValueError:
    i = None
if i and i.get("kb_path"):
    ctx += (f" Resolved for this repo: world `{i['world']}`, project `{i['project']}`,"
            f" KB folder `{i['kb_path']}`, task records under `{i['tasks_path']}`.")
elif i and i.get("ignored"):
    ctx += (f" Project `{i['project']}` is under `ignore:` in the kb manifest:"
            " it has no Outline folder. Ask the operator before writing anything for it.")
elif i:
    cause = i.get("manifest_error") or "repo not declared in the kb manifest, no KB_WORLD"
    ctx += (f" World for project `{i['project']}` is unresolved ({cause});"
            " ask the operator once before writing.")
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": ctx,
    }
}))
PY
