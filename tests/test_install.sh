#!/usr/bin/env bash
# install.sh contract: dry-run by default, --apply to mutate, refuse --apply from a
# linked worktree. A stub `claude` on PATH logs every call, so the real CLI
# registry is never touched. Run: bash tests/test_install.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0
ok()   { echo "ok: $1"; }
fail() { echo "FAIL: $1"; fails=$((fails+1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
calls="$tmp/calls.log"

# Stub CLI: logs its argv; `list` subcommands print $STUB_LIST (empty = nothing installed).
mkdir -p "$tmp/bin"
cat > "$tmp/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_CALLS"
case "$*" in *list*) printf '%s\n' "${STUB_LIST:-}" ;; esac
STUB
chmod +x "$tmp/bin/claude"
export PATH="$tmp/bin:$PATH" STUB_CALLS="$calls"

mutations() { grep -vE '(marketplace list|plugin list)$' "$calls" || true; }

# 1. Default run prints a plan and mutates nothing.
: > "$calls"
out="$("$ROOT/install.sh" </dev/null)"
[ -z "$(mutations)" ] && ok "default run is read-only" || fail "default run mutated: $(mutations)"
grep -q "PLAN: claude plugin marketplace add $ROOT" <<<"$out" || fail "plan missing marketplace add"
grep -q 'PLAN: claude plugin install worklog-persist@worklog-persist-marketplace' <<<"$out" \
  || fail "plan missing plugin install"

# 2. --apply without --yes and with closed stdin aborts before any mutation.
: > "$calls"
rc=0; "$ROOT/install.sh" --apply </dev/null >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] && [ -z "$(mutations)" ] && ok "--apply without consent aborts" \
  || fail "--apply without consent: rc=$rc mutations=$(mutations)"

# 3. --apply --yes runs both mutations.
: > "$calls"
"$ROOT/install.sh" --apply --yes </dev/null >/dev/null
grep -qx "plugin marketplace add $ROOT" "$calls" && grep -qx 'plugin install worklog-persist@worklog-persist-marketplace' "$calls" \
  && ok "--apply --yes installs" || fail "--apply --yes calls: $(cat "$calls")"

# 4. Idempotent: already registered and installed means no mutation.
: > "$calls"
STUB_LIST=$'worklog-persist-marketplace\nworklog-persist@worklog-persist-marketplace' \
  "$ROOT/install.sh" --apply --yes </dev/null >/dev/null
[ -z "$(mutations)" ] && ok "second --apply is a no-op" || fail "second --apply mutated: $(mutations)"

# 5. The same plugin name from another marketplace does not count as installed.
out="$(STUB_LIST='worklog-persist@some-other-marketplace' "$ROOT/install.sh" </dev/null)"
grep -q 'PLAN: claude plugin install worklog-persist@worklog-persist-marketplace' <<<"$out" \
  && ok "foreign marketplace ignored" || fail "foreign marketplace treated as installed"

# 6. --apply from a linked worktree is refused before any mutation.
repo="$tmp/repo"
mkdir -p "$repo" && cp "$ROOT/install.sh" "$repo/"
git -C "$repo" init -q && git -C "$repo" add install.sh \
  && git -C "$repo" -c user.name=t -c user.email=t@t commit -q -m init
git -C "$repo" worktree add -q "$tmp/wt" -b wt
: > "$calls"
rc=0; err="$("$tmp/wt/install.sh" --apply --yes </dev/null 2>&1)" || rc=$?
[ "$rc" != 0 ] && grep -q REFUSING <<<"$err" && [ -z "$(mutations)" ] \
  && ok "--apply refused from linked worktree" || fail "worktree: rc=$rc out=$err"

# 7. Positive control for 6: the main checkout of the same repo is allowed.
: > "$calls"
"$repo/install.sh" --apply --yes </dev/null >/dev/null
grep -qx "plugin marketplace add $repo" "$calls" && ok "--apply allowed from main checkout" \
  || fail "main checkout did not install: $(cat "$calls")"

[ "$fails" = 0 ] && echo "PASS test_install" || { echo "$fails failure(s)"; exit 1; }
