#!/usr/bin/env bash
# Off-switch + SessionStart hook gating. Uses an isolated XDG_STATE_HOME so it
# never touches real state. Run: bash tests/test_offswitch.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0
check() { if [ "$2" != "$3" ]; then echo "FAIL: $1 (want '$3', got '$2')"; fails=$((fails+1)); else echo "ok: $1"; fi; }

export XDG_STATE_HOME="$(mktemp -d)"
trap 'rm -rf "$XDG_STATE_HOME"' EXIT
unset WORKLOG_HOOK_OFF || true

check "default on" "$(bash "$ROOT/scripts/persistence-state.sh" status)" "on"

# When on, the hook emits SessionStart JSON carrying the dedupe marker.
on_out="$(bash "$ROOT/scripts/session-start.sh")"
has_marker="$(printf '%s' "$on_out" | python3 -c "import sys,json;print('Outline (MCP server' in json.load(sys.stdin)['hookSpecificOutput']['additionalContext'])")"
check "hook emits when on" "$has_marker" "True"

# The hook names the resolved KB folder, so the session need not resolve it.
repo="$XDG_STATE_HOME/repo" && mkdir -p "$repo" && git -C "$repo" init -q
has_path="$(cd "$repo" && KB_MANIFEST=/nonexistent KB_WORLD=W bash "$ROOT/scripts/session-start.sh" \
  | python3 -c "import sys,json;print('\`raqz.pl/W/repo\`' in json.load(sys.stdin)['hookSpecificOutput']['additionalContext'])")"
check "hook names kb_path" "$has_path" "True"

# When the world is unresolved, the hook states the real cause (here: manifest error).
has_cause="$(cd "$repo" && KB_MANIFEST=/nonexistent KB_WORLD= bash "$ROOT/scripts/session-start.sh" \
  | python3 -c "import sys,json;print('manifest not found: /nonexistent' in json.load(sys.stdin)['hookSpecificOutput']['additionalContext'])")"
check "hook states unresolved cause" "$has_cause" "True"

bash "$ROOT/scripts/persistence-state.sh" off >/dev/null
check "toggled off" "$(bash "$ROOT/scripts/persistence-state.sh" status)" "off"
check "hook silent when off" "$(bash "$ROOT/scripts/session-start.sh" | wc -c | tr -d ' ')" "0"

bash "$ROOT/scripts/persistence-state.sh" on >/dev/null
check "toggled back on" "$(bash "$ROOT/scripts/persistence-state.sh" status)" "on"

# Env override forces off even without the marker file.
check "env override status" "$(WORKLOG_HOOK_OFF=1 bash "$ROOT/scripts/persistence-state.sh" status)" "off"
check "env override silences hook" "$(WORKLOG_HOOK_OFF=1 bash "$ROOT/scripts/session-start.sh" | wc -c | tr -d ' ')" "0"

[ "$fails" = 0 ] && echo "PASS test_offswitch" || { echo "$fails failure(s)"; exit 1; }
