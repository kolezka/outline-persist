#!/usr/bin/env bash
# Plugin discovery + idempotent structure validation + foreign-config safety.
# Run: bash tests/test_structure.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0
note() { echo "$1"; }
fail() { echo "FAIL: $1"; fails=$((fails+1)); }

# 1. --check passes and is idempotent (same result on repeat).
"$ROOT/install.sh" --check >/dev/null || fail "install.sh --check failed"
"$ROOT/install.sh" --check >/dev/null || fail "install.sh --check not idempotent"
note "ok: structure valid and idempotent"

# 2. .mcp.json defines exactly the outline server (reuse, no duplicate, no second client).
servers="$(python3 -c "import json;print(','.join(json.load(open('$ROOT/.mcp.json'))['mcpServers']))")"
[ "$servers" = "outline" ] || fail ".mcp.json servers = '$servers', want 'outline'"
note "ok: single outline MCP server"

# 3. No hardcoded credentials anywhere (only \${ENV} placeholders).
if grep -RInE '(Bearer [A-Za-z0-9]{12,}|CF_ACCESS_CLIENT_SECRET=.+[A-Za-z0-9])' "$ROOT/.mcp.json"; then
  fail "possible hardcoded credential in .mcp.json"
fi
grep -q '${OUTLINE_API_TOKEN}' "$ROOT/.mcp.json" || fail ".mcp.json should use \${OUTLINE_API_TOKEN} placeholder"
note "ok: credentials are env placeholders only"

# 4. hooks.json uses the plugin (wrapped) shape and the dedupe marker text.
python3 -c "import json;h=json.load(open('$ROOT/hooks/hooks.json'));assert h['hooks']['SessionStart']" \
  || fail "hooks.json missing wrapped SessionStart"
grep -q 'Outline (MCP server' "$ROOT/scripts/session-start.sh" || fail "session-start.sh missing dedupe marker"
note "ok: hooks wrapped + marker present"

# 5. All 7 verbs exist as commands.
for c in load start checkpoint handoff complete dry-run off; do
  [ -f "$ROOT/commands/$c.md" ] || fail "missing command: $c"
done
note "ok: all 7 verb commands present"

[ "$fails" = 0 ] && echo "PASS test_structure" || { echo "$fails failure(s)"; exit 1; }
