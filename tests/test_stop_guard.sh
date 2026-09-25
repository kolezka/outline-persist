#!/usr/bin/env bash
# Stop-hook tests for scripts/stop-guard.sh. Uses an isolated XDG_STATE_HOME and
# KB_MANIFEST so it never touches real state. Run: bash tests/test_stop_guard.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/stop-guard.sh"
fails=0
check() { if [ "$2" != "$3" ]; then echo "FAIL: $1 (want '$3', got '$2')"; fails=$((fails+1)); else echo "ok: $1"; fi; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

XDG_STATE_HOME="$tmp/state"
export XDG_STATE_HOME
mkdir -p "$XDG_STATE_HOME"
unset WORKLOG_HOOK_OFF WORKLOG_STOP_MIN_TOOLS || true
# Isolate from the host kb manifest so world resolution stays deterministic.
export KB_MANIFEST="$tmp/none.yaml"

cwd_dir="$tmp/work"
mkdir -p "$cwd_dir"

# Build the Stop-hook stdin JSON for a given transcript file. Session id
# defaults to "s1", the fixed id used by every case that predates the marker.
input() {
  python3 -c '
import json, sys
print(json.dumps({
    "session_id": sys.argv[4],
    "transcript_path": sys.argv[1],
    "cwd": sys.argv[2],
    "stop_hook_active": sys.argv[3] == "true",
}))
' "$1" "$2" "$3" "${4:-s1}"
}

decision() {
  # Reads stop-guard stdout; prints the "decision" field, or "" for empty/no output.
  python3 -c '
import json, sys
raw = sys.stdin.read().strip()
if not raw:
    print("")
else:
    print(json.loads(raw).get("decision", ""))
'
}

run_guard() {
  local transcript="$1" active="${2:-false}" session="${3:-s1}"
  input "$transcript" "$cwd_dir" "$active" "$session" | bash "$SCRIPT"
}

# Fixture: no tool_use at all.
t_no_work="$tmp/no_work.jsonl"
cat > "$t_no_work" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"hello"}]}}
EOF

# Fixture: one Edit, no Outline write ever.
t_edit_no_write="$tmp/edit_no_write.jsonl"
cat > "$t_edit_no_write" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"a.py"}}]}}
EOF

# Fixture: Edit, then a user-scope Outline update_document afterward.
t_edit_then_write="$tmp/edit_then_write.jsonl"
cat > "$t_edit_then_write" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"a.py"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__outline__update_document","input":{}}]}}
EOF

# Fixture: the same Edit, but it happened on a subagent (sidechain) transcript line.
t_sidechain="$tmp/sidechain.jsonl"
cat > "$t_sidechain" <<'EOF'
{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"a.py"}}]}}
EOF

# Fixture: Edit, then a plugin-scoped Outline write (not the bare mcp__outline__ prefix).
t_plugin_write="$tmp/plugin_write.jsonl"
cat > "$t_plugin_write" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"a.py"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__plugin_worklog-persist_outline__create_document","input":{}}]}}
EOF

# Fixture: unparsable content, must never crash the hook.
t_garbage="$tmp/garbage.jsonl"
cat > "$t_garbage" <<'EOF'
not json at all {{{
{"type":"assistant","message":
EOF

# Each case below uses its own session id: these fixtures are independent
# hypothetical sessions, and giving them distinct ids keeps one case's marker
# from leaking into another's (the marker cases further down test the sharing
# deliberately, with explicit shared/distinct ids of their own).

# Case 1: no substantive work at all -> allow, silent.
out="$(run_guard "$t_no_work" false "case1")"
check "no work: silent" "$out" ""

# Case 2: an Edit since the (nonexistent) last write -> block.
out="$(run_guard "$t_edit_no_write" false "case2")"
check "edit no write: decision" "$(printf '%s' "$out" | decision)" "block"
check "edit no write: mentions checkpoint" "$(printf '%s' "$out" | grep -c 'worklog-persist skill')" "1"

# Case 3: an Outline write after the Edit clears the slate -> allow.
out="$(run_guard "$t_edit_then_write" false "case3")"
check "edit then write: silent" "$out" ""

# Case 4: stop_hook_active=true always allows, even with unpersisted Edits.
out="$(run_guard "$t_edit_no_write" true "case4")"
check "stop_hook_active: silent" "$out" ""

# Case 5: persistence off (WORKLOG_HOOK_OFF=1) always allows.
out="$(WORKLOG_HOOK_OFF=1 bash -c "$(declare -f input); input '$t_edit_no_write' '$cwd_dir' false 'case5'" | WORKLOG_HOOK_OFF=1 bash "$SCRIPT")"
check "persistence off: silent" "$out" ""

# Case 6: the only Edit is on a sidechain (subagent) line -> ignored -> allow.
out="$(run_guard "$t_sidechain" false "case6")"
check "sidechain only: silent" "$out" ""

# Case 7: a plugin-prefixed Outline write counts as a write, clearing the slate.
out="$(run_guard "$t_plugin_write" false "case7")"
check "plugin-prefixed write: silent" "$out" ""

# Case 8: a garbage transcript must never crash the hook; unparsable lines are
# skipped, so with no real tool_use found the result is a silent allow.
out="$(run_guard "$t_garbage" false "case8")"
check "garbage transcript: silent" "$out" ""
rc=0; run_guard "$t_garbage" false "case8" >/dev/null 2>&1 || rc=$?
check "garbage transcript: exit 0" "$rc" "0"

# Case 9: WORKLOG_STOP_MIN_TOOLS makes a long run of small tool calls substantive
# even with no Edit/Write/Bash among them. The two sub-cases use different
# session ids so the first one's block-and-record does not clear the slate for
# the second, which needs the full 5 tool_uses to test the threshold itself.
t_many="$tmp/many.jsonl"
: > "$t_many"
for _ in $(seq 1 5); do
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{}}]}}\n' >> "$t_many"
done
out="$(WORKLOG_STOP_MIN_TOOLS=5 bash -c "$(declare -f input); input '$t_many' '$cwd_dir' false 'case9-block'" | WORKLOG_STOP_MIN_TOOLS=5 bash "$SCRIPT")"
check "min-tools threshold: decision" "$(printf '%s' "$out" | decision)" "block"
out="$(run_guard "$t_many" false "case9-below")"
check "below default threshold: silent" "$out" ""

# Fixture dedicated to the per-session decline marker below. Mutated in place
# by case 11, so it is kept separate from the fixed transcripts used above. The
# marker stores a tool_use id, so these fixtures need real ids (unlike the
# fixtures above, which never rely on marker persistence for their result).
t_marker="$tmp/marker.jsonl"
cat > "$t_marker" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu-a1","name":"Edit","input":{"file_path":"a.py"}}]}}
EOF

# Case 10: a block is recorded for this session; the same transcript, not
# extended further, does not re-block the next stop (a decline is honoured
# once the work behind it has actually been shown).
out="$(run_guard "$t_marker" false "sess-a")"
check "marker: first block" "$(printf '%s' "$out" | decision)" "block"
out="$(run_guard "$t_marker" false "sess-a")"
check "marker: declined work not re-nagged" "$out" ""

# Case 11: new work appended after the decline blocks again, same session.
cat >> "$t_marker" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu-a2","name":"Edit","input":{"file_path":"b.py"}}]}}
EOF
out="$(run_guard "$t_marker" false "sess-a")"
check "marker: new work after decline blocks again" "$(printf '%s' "$out" | decision)" "block"

# Case 12: a different session has no marker of its own, so the same
# transcript still blocks for it even though sess-a just saw this work.
out="$(run_guard "$t_marker" false "sess-b")"
check "marker: different session still blocks" "$(printf '%s' "$out" | decision)" "block"

# Case 13: a recorded marker id that no longer appears in the transcript is
# treated as absent (falls back to the last write) rather than trusting a
# stale marker forever or blocking on every single turn regardless of id.
t_missing_a="$tmp/marker_missing_a.jsonl"
cat > "$t_missing_a" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu-x","name":"Edit","input":{"file_path":"a.py"}}]}}
EOF
out="$(run_guard "$t_missing_a" false "sess-c")"
check "marker: setup block to record tu-x for sess-c" "$(printf '%s' "$out" | decision)" "block"

t_missing_b="$tmp/marker_missing_b.jsonl"
cat > "$t_missing_b" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu-z","name":"Edit","input":{"file_path":"c.py"}}]}}
EOF
out="$(run_guard "$t_missing_b" false "sess-c")"
check "marker: id missing from transcript falls back and blocks" "$(printf '%s' "$out" | decision)" "block"

# COMMIT_RE unit cases: a git subcommand behind -C/-c global options is still
# caught, a lookalike subcommand (commit-tree) is not, and gh pr create counts.
commit_re() {
  python3 -c "
import sys
sys.path.insert(0, '$ROOT/scripts')
import stop_guard as m
print(bool(m.COMMIT_RE.search(sys.argv[1])))
" "$1"
}
check "COMMIT_RE: plain commit" "$(commit_re 'git commit -m x')" "True"
check "COMMIT_RE: plain push" "$(commit_re 'git push origin main')" "True"
check "COMMIT_RE: -C option before commit" "$(commit_re 'git -C /repo commit -m x')" "True"
check "COMMIT_RE: -c option before commit" "$(commit_re 'git -c user.email=a@b commit')" "True"
check "COMMIT_RE: commit-tree is not commit" "$(commit_re 'git commit-tree -m x')" "False"
check "COMMIT_RE: unrelated git command" "$(commit_re 'git checkout -- file')" "False"
check "COMMIT_RE: gh pr create" "$(commit_re 'gh pr create --title x')" "True"
check "COMMIT_RE: chained -C and -c before push" \
  "$(commit_re 'git -C /repo -c user.name=a push')" "True"

# Case: resolve-context.sh failing outright (not just returning UNRESOLVED) still
# blocks, with a generic reason that makes no world claim. Uses a copy of scripts/
# with a broken resolve-context.sh; everything else (persistence-state.sh, the
# hook itself) is the real, unmodified script.
broken="$tmp/broken-scripts"
mkdir -p "$broken"
cp "$ROOT"/scripts/*.sh "$ROOT"/scripts/*.py "$broken"/
printf '#!/usr/bin/env bash\nexit 1\n' > "$broken/resolve-context.sh"
t_broken="$tmp/broken_ctx.jsonl"
cat > "$t_broken" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu-broken","name":"Edit","input":{"file_path":"a.py"}}]}}
EOF
out="$(input "$t_broken" "$cwd_dir" false "sess-broken" | bash "$broken/stop-guard.sh")"
check "resolve-context failure: still blocks" "$(printf '%s' "$out" | decision)" "block"
check "resolve-context failure: no world claim in reason" \
  "$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("Resolved context" not in d["reason"] and "resolves the path" in d["reason"])')" \
  "True"

[ "$fails" = 0 ] && echo "PASS test_stop_guard" || { echo "$fails failure(s)"; exit 1; }
