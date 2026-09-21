#!/usr/bin/env bash
# Identity + world resolution tests for scripts/resolve-context.sh.
# World-agnostic: no world name is ever hardcoded; it comes from $KB_WORLD or the
# UNRESOLVED sentinel. Run: bash tests/test_context.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/resolve-context.sh"
fails=0
check() { if [ "$2" != "$3" ]; then echo "FAIL: $1 (want '$3', got '$2')"; fails=$((fails+1)); else echo "ok: $1"; fi; }
field() { python3 -c "import sys,json;print(json.load(sys.stdin)['$1'])"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Case 1: git repo, no remote -> project = dir name, world = UNRESOLVED sentinel.
mkdir -p "$tmp/myproj" && git -C "$tmp/myproj" init -q && git -C "$tmp/myproj" commit -q --allow-empty -m init
out="$(cd "$tmp/myproj" && KB_WORLD= bash "$SCRIPT")"
check "no-remote project" "$(printf '%s' "$out" | field project)" "myproj"
check "no-remote world sentinel" "$(printf '%s' "$out" | field world)" "UNRESOLVED"

# Case 2: KB_WORLD overrides -> proves world is NOT hardcoded.
out="$(cd "$tmp/myproj" && KB_WORLD=SomeWorld bash "$SCRIPT")"
check "KB_WORLD honored" "$(printf '%s' "$out" | field world)" "SomeWorld"

# Case 3: remote origin -> project = repo basename sans .git.
git -C "$tmp/myproj" remote add origin "git@github.com:acme/coolrepo.git"
out="$(cd "$tmp/myproj" && bash "$SCRIPT")"
check "remote project basename" "$(printf '%s' "$out" | field project)" "coolrepo"

# Case 4: valid kebab slug preserved.
out="$(cd "$tmp/myproj" && bash "$SCRIPT" my-task-123)"
check "valid slug" "$(printf '%s' "$out" | field task_slug)" "my-task-123"

# Case 5: invalid slug rejected (exit 2).
rc=0; (cd "$tmp/myproj" && bash "$SCRIPT" "Bad_Slug") >/dev/null 2>&1 || rc=$?
check "invalid slug rejected" "$rc" "2"

# Invariant: resolve-context.sh hardcodes no world name; only env + sentinel.
lits="$(grep -c 'world="' "$SCRIPT" || true)"
check "single world assignment" "$lits" "1"
grep -q 'world="${KB_WORLD:-UNRESOLVED}"' "$SCRIPT" || { echo "FAIL: world not sourced from KB_WORLD/sentinel"; fails=$((fails+1)); }

[ "$fails" = 0 ] && echo "PASS test_context" || { echo "$fails failure(s)"; exit 1; }
