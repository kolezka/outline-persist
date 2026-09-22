#!/usr/bin/env bash
# Install / enable / disable the worklog-persist plugin locally.
#
# worklog-persist ships as a self-contained Claude Code plugin with its own local
# marketplace (.claude-plugin/marketplace.json). Installation registers that
# marketplace and installs the plugin through the `claude` CLI, which manages its
# own registry — so unrelated marketplaces, plugins, MCP servers and hooks are
# left untouched. Nothing here edits settings.json or a shared mcp.json.
#
# Usage:
#   ./install.sh [--dry-run]     install (idempotent)
#   ./install.sh --check         validate plugin structure only (no claude needed)
#   ./install.sh --enable        re-enable an installed plugin
#   ./install.sh --disable       disable without uninstalling
#   ./install.sh --uninstall     remove the plugin
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="worklog-persist"
MARKET="worklog-persist-marketplace"
DRY=0

log()  { printf '%s\n' "$*"; }
run()  { if [ "$DRY" = 1 ]; then log "DRY: $*"; else "$@"; fi; }

# --- structure validation (no external deps beyond python3) ------------------
check_structure() {
  local ok=1
  _fail() { log "FAIL: $*"; ok=0; }

  python3 - "$ROOT" <<'PY' || exit 1
import json, sys, pathlib
root = pathlib.Path(sys.argv[1])
errs = []

def load(p):
    try:
        return json.loads((root / p).read_text())
    except Exception as e:  # noqa: BLE001
        errs.append(f"{p}: {e}")
        return None

man = load(".claude-plugin/plugin.json")
if man is not None and man.get("name") != "worklog-persist":
    errs.append("plugin.json name must be 'worklog-persist'")

mkt = load(".claude-plugin/marketplace.json")
if mkt is not None:
    names = [p.get("name") for p in mkt.get("plugins", [])]
    if "worklog-persist" not in names:
        errs.append("marketplace.json must list plugin 'worklog-persist'")

hooks = load("hooks/hooks.json")
if hooks is not None:
    ss = hooks.get("hooks", {}).get("SessionStart")
    if not ss:
        errs.append("hooks.json must wrap SessionStart under a top-level 'hooks' key")

mcp = load(".mcp.json")
if mcp is not None:
    servers = list(mcp.get("mcpServers", {}))
    if servers != ["outline"]:
        errs.append(f".mcp.json must define exactly the 'outline' server, got {servers}")

need_cmds = {"load", "start", "checkpoint", "handoff", "complete", "dry-run", "off"}
have = {p.stem for p in (root / "commands").glob("*.md")}
missing = need_cmds - have
if missing:
    errs.append(f"missing commands: {sorted(missing)}")

if not (root / "skills/worklog-persist/SKILL.md").is_file():
    errs.append("missing skills/worklog-persist/SKILL.md")

for s in ("session-start.sh", "resolve-context.sh", "persistence-state.sh", "redact.py"):
    if not (root / "scripts" / s).is_file():
        errs.append(f"missing scripts/{s}")

if errs:
    print("STRUCTURE INVALID:")
    for e in errs:
        print("  -", e)
    sys.exit(1)
print("structure OK: worklog-persist plugin is well-formed")
PY
}

require_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    log "error: 'claude' CLI not found on PATH. Install Claude Code first, or run --check." >&2
    exit 127
  fi
}

marketplace_present() { claude plugin marketplace list 2>/dev/null | grep -q "$MARKET"; }
plugin_present()      { claude plugin list 2>/dev/null | grep -q "$PLUGIN"; }

do_install() {
  require_claude
  if marketplace_present; then
    log "marketplace '$MARKET' already registered — skipping add (idempotent)"
  else
    run claude plugin marketplace add "$ROOT"
  fi
  if plugin_present; then
    log "plugin '$PLUGIN' already installed — skipping install (idempotent)"
  else
    run claude plugin install "${PLUGIN}@${MARKET}"
  fi
  log "done. Enable/disable automatic persistence with: /off  (or scripts/persistence-state.sh)"
}

case "${1:-}" in
  --check)     check_structure ;;
  --dry-run)   DRY=1; do_install ;;
  --enable)    require_claude; run claude plugin enable "$PLUGIN" ;;
  --disable)   require_claude; run claude plugin disable "$PLUGIN" ;;
  --uninstall) require_claude; run claude plugin uninstall "$PLUGIN" ;;
  ""|--install) do_install ;;
  *) log "usage: install.sh [--dry-run|--check|--enable|--disable|--uninstall]" >&2; exit 2 ;;
esac
