#!/usr/bin/env bash
# scripts/config-add.sh: the only sanctioned writer of the plugin config.
# Every case runs against a scratch WORKLOG_CONFIG. Run: bash tests/test_config_add.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADD="$ROOT/scripts/config-add.sh"
RESOLVE="$ROOT/scripts/resolve-context.sh"
fails=0
check() { if [ "$2" != "$3" ]; then echo "FAIL: $1 (want '$3', got '$2')"; fails=$((fails+1)); else echo "ok: $1"; fi; }
sum() { if [ -f "$1" ]; then shasum "$1" | cut -d' ' -f1; else echo absent; fi; }
ident() { python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["world"],d["world_source"],d["project"],d["kb_path"],d["ignored"])'; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
unset WORKLOG_WORLD || true
cfg="$tmp/nested/dir/config.yaml"
export WORKLOG_CONFIG="$cfg"
for r in one two three; do
  mkdir -p "$tmp/$r" && git -C "$tmp/$r" init -q && git -C "$tmp/$r" commit -q --allow-empty -m init
done
one="$(cd "$tmp/one" && pwd -P)"

# 1. Missing file and parent dirs are created; the resolver then routes the repo.
rc=0; bash "$ADD" project --world Alpha --name proj-one --repo "$tmp/one" >/dev/null || rc=$?
check "create file: exit 0" "$rc" "0"
check "create file: exists" "$(test -f "$cfg" && echo yes)" "yes"
check "create file: resolves" "$(cd "$tmp/one" && bash "$RESOLVE" | ident)" "Alpha config proj-one raqz.pl/Alpha/proj-one False"

# 2. Re-adding the same declaration is a no-op: exit 0 and the file is untouched.
before="$(sum "$cfg")"
rc=0; out="$(bash "$ADD" project --world Alpha --name proj-one --repo "$tmp/one")" || rc=$?
check "idempotent re-add: exit 0" "$rc" "0"
check "idempotent re-add: byte-identical" "$(sum "$cfg")" "$before"
check "idempotent re-add: says so" "$(grep -c 'no change' <<<"$out")" "1"

# 3. The same repo under a different world is an error, never a silent move.
rc=0; bash "$ADD" project --world Beta --name proj-one --repo "$tmp/one" >/dev/null 2>&1 || rc=$?
check "conflict: non-zero exit" "$([ "$rc" != 0 ] && echo yes)" "yes"
check "conflict: file untouched" "$(sum "$cfg")" "$before"

# 4. A second project and a kb_folder keep the first entry intact.
bash "$ADD" project --world Alpha --name proj-two --repo "$tmp/two" --kb-folder "KB/Alpha/custom" >/dev/null || true
check "second project: first kept" "$(cd "$tmp/one" && bash "$RESOLVE" | ident)" "Alpha config proj-one raqz.pl/Alpha/proj-one False"
check "second project: kb_folder" "$(cd "$tmp/two" && bash "$RESOLVE" | ident)" "Alpha config proj-two KB/Alpha/custom False"
check "one world entry" "$(python3 -c 'import sys,yaml;print([w["name"] for w in yaml.safe_load(open(sys.argv[1]))["worlds"]])' "$cfg")" "['Alpha']"

# 5. An ignore entry makes the repo ignored; repeating it is a no-op.
bash "$ADD" ignore --repo "$tmp/three" >/dev/null || true
check "ignore: resolves ignored" "$(cd "$tmp/three" && WORKLOG_WORLD=E bash "$RESOLVE" | ident)" "UNRESOLVED fallback three None True"
before="$(sum "$cfg")"
bash "$ADD" ignore --repo "$tmp/three" >/dev/null || true
check "ignore: idempotent" "$(sum "$cfg")" "$before"
# A declared repo cannot also be ignored, and an ignored one cannot be declared.
rc=0; bash "$ADD" ignore --repo "$tmp/one" >/dev/null 2>&1 || rc=$?
check "ignore declared repo: refused" "$([ "$rc" != 0 ] && echo yes) $(sum "$cfg")" "yes $before"
rc=0; bash "$ADD" project --world Alpha --name three --repo "$tmp/three" >/dev/null 2>&1 || rc=$?
check "declare ignored repo: refused" "$([ "$rc" != 0 ] && echo yes) $(sum "$cfg")" "yes $before"

# 6. Paths are stored resolved, so the resolver matches them from any spelling.
check "stored path is resolved" "$(python3 -c 'import sys,yaml;print(yaml.safe_load(open(sys.argv[1]))["worlds"][0]["projects"][0]["repo"])' "$cfg")" "$one"

# 7. No temp file is left next to the config after a write.
check "atomic write leaves no temp file" "$(find "$(dirname "$cfg")" -type f | wc -l | tr -d ' ')" "1"

# 8. A file it cannot parse, or with the wrong shape, is refused and left byte-identical.
printf 'worlds:\n  - name: [unclosed\n' > "$tmp/garbage.yaml"
before="$(sum "$tmp/garbage.yaml")"
rc=0; WORKLOG_CONFIG="$tmp/garbage.yaml" bash "$ADD" project --world A --name n --repo "$tmp/one" >/dev/null 2>&1 || rc=$?
check "unparseable file refused" "$([ "$rc" != 0 ] && echo yes) $(sum "$tmp/garbage.yaml")" "yes $before"
printf 'outline: [x]\nworlds: [a, b]\nignore: 3\n' > "$tmp/bad.yaml"
before="$(sum "$tmp/bad.yaml")"
rc=0; WORKLOG_CONFIG="$tmp/bad.yaml" bash "$ADD" ignore --repo "$tmp/one" >/dev/null 2>&1 || rc=$?
check "malformed file refused" "$([ "$rc" != 0 ] && echo yes) $(sum "$tmp/bad.yaml")" "yes $before"

# 9. Without PyYAML it reports the cause and writes nothing.
mkdir -p "$tmp/noyaml" && echo 'raise ImportError("stub")' > "$tmp/noyaml/yaml.py"
rc=0; err="$(PYTHONPATH="$tmp/noyaml" WORKLOG_CONFIG="$tmp/fresh.yaml" bash "$ADD" ignore --repo "$tmp/one" 2>&1)" || rc=$?
check "no PyYAML: refused, nothing written" "$([ "$rc" != 0 ] && echo yes) $(sum "$tmp/fresh.yaml")" "yes absent"
check "no PyYAML: names the cause" "$(grep -c 'PyYAML' <<<"$err")" "1"

# 10. Bad arguments are rejected before any write.
rc=0; WORKLOG_CONFIG="$tmp/fresh.yaml" bash "$ADD" project --world 'A/B' --name n --repo "$tmp/one" >/dev/null 2>&1 || rc=$?
check "world with slash refused" "$([ "$rc" != 0 ] && echo yes) $(sum "$tmp/fresh.yaml")" "yes absent"

# 11. A symlinked config (dotfiles) stays a symlink; the entry lands in its target.
mkdir -p "$tmp/dotfiles" "$tmp/linkdir"
printf 'worlds: []\n' > "$tmp/dotfiles/config.yaml" && chmod 600 "$tmp/dotfiles/config.yaml"
ln -s "$tmp/dotfiles/config.yaml" "$tmp/linkdir/config.yaml"
rc=0; WORKLOG_CONFIG="$tmp/linkdir/config.yaml" bash "$ADD" project --world Alpha --name linked --repo "$tmp/one" >/dev/null 2>&1 || rc=$?
check "symlink: exit 0" "$rc" "0"
check "symlink: still a symlink" "$(test -L "$tmp/linkdir/config.yaml" && echo yes)" "yes"
check "symlink: target has entry" "$(grep -c 'name: linked' "$tmp/dotfiles/config.yaml")" "1"
check "symlink: target mode kept" "$(python3 -c 'import os,sys;print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$tmp/dotfiles/config.yaml")" "0o600"
check "symlink: no temp file left" "$(find "$tmp/dotfiles" "$tmp/linkdir" -name '*.tmp' | wc -l | tr -d ' ')" "0"

[ "$fails" = 0 ] && echo "PASS test_config_add" || { echo "$fails failure(s)"; exit 1; }
