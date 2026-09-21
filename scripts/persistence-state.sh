#!/usr/bin/env bash
# Manage the outline-persist off-state file.
#
# The off-state is a single marker file. When it exists, or OUTLINE_HOOK_OFF=1,
# automatic session-start persistence is disabled. The plugin stays installed.
#
# Usage:
#   persistence-state.sh path      # print the state file path
#   persistence-state.sh status    # print "on" or "off" (also honors OUTLINE_HOOK_OFF)
#   persistence-state.sh off       # create the marker (disable)
#   persistence-state.sh on        # remove the marker (enable)
set -euo pipefail

state_dir() {
  printf '%s/outline-persist' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

state_file() {
  printf '%s/off' "$(state_dir)"
}

is_off() {
  [ "${OUTLINE_HOOK_OFF:-}" = 1 ] && return 0
  [ -e "$(state_file)" ] && return 0
  return 1
}

cmd="${1:-status}"
case "$cmd" in
  path)
    state_file
    ;;
  status)
    if is_off; then echo off; else echo on; fi
    ;;
  off)
    mkdir -p "$(state_dir)"
    : > "$(state_file)"
    echo "outline-persist: automatic persistence disabled ($(state_file))"
    ;;
  on)
    rm -f "$(state_file)"
    if [ "${OUTLINE_HOOK_OFF:-}" = 1 ]; then
      echo "outline-persist: off-file cleared, but OUTLINE_HOOK_OFF=1 still disables it"
    else
      echo "outline-persist: automatic persistence enabled"
    fi
    ;;
  *)
    echo "usage: persistence-state.sh {path|status|off|on}" >&2
    exit 2
    ;;
esac
