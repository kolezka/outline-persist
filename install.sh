#!/usr/bin/env bash
# Install / enable / disable the worklog-persist plugin locally.
#
# worklog-persist ships as a self-contained Claude Code plugin with its own local
# marketplace (.claude-plugin/marketplace.json). Installation registers that
# marketplace and installs the plugin through the `claude` CLI, which manages its
# own registry, so unrelated marketplaces, plugins, MCP servers and hooks are
# left untouched. Nothing here edits settings.json or a shared mcp.json.
#
# Dry-run by default: without --apply every mutating step is printed, not run.
#
# Usage:
#   ./install.sh [--apply [--yes]]                install (idempotent)
#   ./install.sh [--apply [--yes]] --enable       re-enable an installed plugin
#   ./install.sh [--apply [--yes]] --disable      disable without uninstalling
#   ./install.sh [--apply [--yes]] --uninstall    remove the plugin
#   ./install.sh --check                          validate plugin structure only
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="worklog-persist"
MARKET="worklog-persist-marketplace"
APPLY=0
YES=0
ACTION=install

log() { printf '%s\n' "$*"; }

# Print the step, then run it only with --apply, asking first unless --yes.
# The answer comes from stdin, so a closed stdin means "no".
step() {
  if [ "$APPLY" = 0 ]; then
    log "PLAN: $*"
    return 0
  fi
  if [ "$YES" = 0 ]; then
    printf 'run: %s ? [y/N] ' "$*"
    local answer=""
    read -r answer || true
    case "$answer" in
      y|Y|yes) ;;
      *) log "aborted: $*"; exit 1 ;;
    esac
  fi
  "$@"
}

# `marketplace add` records $ROOT. From a linked worktree that path dies with the
# branch, and the installed plugin silently stops loading.
require_main_checkout() {
  local git_dir common_dir
  git_dir="$(git -C "$ROOT" rev-parse --git-dir 2>/dev/null)" || return 0
  common_dir="$(git -C "$ROOT" rev-parse --git-common-dir)"
  if [ "$git_dir" != "$common_dir" ]; then
    log "REFUSING: $ROOT is a linked git worktree." >&2
    log "  The marketplace would point at a checkout that is deleted with its branch." >&2
    log "  Run --apply from the main checkout." >&2
    exit 1
  fi
}

# --- structure validation (no external deps beyond python3) ------------------
check_structure() {
  python3 - "$ROOT" <<'PY'
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
plugin_present()      { claude plugin list 2>/dev/null | grep -q "${PLUGIN}@${MARKET}"; }

do_install() {
  require_claude
  [ "$APPLY" = 1 ] && require_main_checkout
  if marketplace_present; then
    log "marketplace '$MARKET' already registered, skipping add"
  else
    step claude plugin marketplace add "$ROOT"
  fi
  if plugin_present; then
    log "plugin '$PLUGIN' already installed, skipping install"
  else
    step claude plugin install "${PLUGIN}@${MARKET}"
  fi
  if [ "$APPLY" = 0 ]; then
    log "dry-run: nothing changed. Re-run with --apply to execute."
  else
    log "done. Toggle automatic persistence with /off or scripts/persistence-state.sh"
  fi
}

usage() {
  log "usage: install.sh [--apply [--yes]] [--enable|--disable|--uninstall] | --check" >&2
  exit 2
}

for arg in "$@"; do
  case "$arg" in
    --apply)     APPLY=1 ;;
    --yes)       YES=1 ;;
    --dry-run)   APPLY=0 ;;
    --check)     ACTION=check ;;
    --install)   ACTION=install ;;
    --enable)    ACTION=enable ;;
    --disable)   ACTION=disable ;;
    --uninstall) ACTION=uninstall ;;
    *) usage ;;
  esac
done

case "$ACTION" in
  check)     check_structure ;;
  install)   do_install ;;
  enable)    require_claude; step claude plugin enable "$PLUGIN" ;;
  disable)   require_claude; step claude plugin disable "$PLUGIN" ;;
  uninstall) require_claude; step claude plugin uninstall "$PLUGIN" ;;
esac
