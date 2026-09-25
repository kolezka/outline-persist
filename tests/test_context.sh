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
# Isolate from the host manifest and env.
unset KB_WORLD OUTLINE_ROOT || true
export KB_MANIFEST="$tmp/none.yaml"

# Case 1: git repo, no remote -> project = dir name, world = UNRESOLVED sentinel.
mkdir -p "$tmp/myproj" && git -C "$tmp/myproj" init -q && git -C "$tmp/myproj" commit -q --allow-empty -m init
out="$(cd "$tmp/myproj" && KB_WORLD='' bash "$SCRIPT")"
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
out="$(cd "$tmp/myproj" && bash "$SCRIPT" AD-163-uat-checklist)"
check "ticket slug" "$(printf '%s' "$out" | field task_slug)" "AD-163-uat-checklist"

# Case 5: invalid slug rejected (exit 2).
rc=0; (cd "$tmp/myproj" && bash "$SCRIPT" "Bad_Slug") >/dev/null 2>&1 || rc=$?
check "invalid slug rejected" "$rc" "2"

# Manifest fixture: custom collections, a declared project whose name differs from
# the directory, a kb_folder override, and an ignored repo.
mkdir -p "$tmp/other" "$tmp/skipme"
git -C "$tmp/other" init -q && git -C "$tmp/other" commit -q --allow-empty -m init
git -C "$tmp/skipme" init -q && git -C "$tmp/skipme" commit -q --allow-empty -m init
cat > "$tmp/worlds.yaml" <<EOF
version: 1
outline:
  base_url: https://example.invalid
  root_collection: RootKB
  global_collection: Notebook
  archive_collection: Attic
worlds:
  - name: Alpha
    projects:
      - {name: declared-name, repo: $tmp/myproj}
  - name: Beta
    projects:
      - {name: other, repo: $tmp/other, kb_folder: RootKB/Beta/custom-folder}
ignore:
  - $tmp/skipme
EOF
export KB_MANIFEST="$tmp/worlds.yaml"

# Case 6: declared repo -> world, name and collections from the manifest, which
# beats KB_WORLD.
out="$(cd "$tmp/myproj" && KB_WORLD=Wrong bash "$SCRIPT" t)"
check "manifest identity" "$(printf '%s' "$out" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["world"],d["world_source"],d["project"],d["record_path"],d["global_collection"],d["archive_collection"])')" \
  "Alpha manifest declared-name RootKB/Alpha/declared-name/Tasks/t Notebook Attic"

# Case 7: a linked worktree maps to its main checkout's project, not its dir name.
git -C "$tmp/myproj" worktree add -q -b feat/x "$tmp/wt-elsewhere"
out="$(cd "$tmp/wt-elsewhere" && bash "$SCRIPT")"
check "worktree identity" "$(printf '%s' "$out" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["project"],d["branch"],d["repo_root"])')" \
  "declared-name feat/x $(cd "$tmp/myproj" && pwd -P)"

# A checkout whose git dir lives elsewhere is still its own main checkout.
mkdir -p "$tmp/store" && git init -q --separate-git-dir "$tmp/store/.git" "$tmp/sep"
check "separate git dir" "$(cd "$tmp/sep" && bash "$SCRIPT" | field repo_root)" "$(cd "$tmp/sep" && pwd -P)"

# Case 8: kb_folder override is used verbatim.
out="$(cd "$tmp/other" && bash "$SCRIPT" t)"
check "kb_folder override" "$(printf '%s' "$out" | field tasks_path)" "RootKB/Beta/custom-folder/Tasks"

# Case 9: an ignored repo is flagged, gets no world, and offers the candidates.
out="$(cd "$tmp/skipme" && bash "$SCRIPT")"
check "ignored repo" "$(printf '%s' "$out" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["ignored"],d["world"],d["kb_path"],",".join(d["candidate_worlds"]))')" \
  "True UNRESOLVED None Alpha,Beta"
# KB_WORLD must not route an ignored repo.
check "ignored beats KB_WORLD" "$(cd "$tmp/skipme" && KB_WORLD=E bash "$SCRIPT" | field kb_path)" "None"
# A repo below an ignored dir is ignored too, as in kb discovery.
mkdir -p "$tmp/skipme/sub" && git -C "$tmp/skipme/sub" init -q
check "nested ignored" "$(cd "$tmp/skipme/sub" && bash "$SCRIPT" | field ignored)" "True"

# Case 10: the mirror dir drops the root-collection segment and must exist.
export OUTLINE_ROOT="$tmp/okb"
before="$(cd "$tmp/myproj" && bash "$SCRIPT" | field mirror_dir)"
mkdir -p "$tmp/okb/outline-sync/Alpha/declared-name"
after="$(cd "$tmp/myproj" && bash "$SCRIPT" | field mirror_dir)"
check "mirror dir" "$before $after" "None $tmp/okb/outline-sync/Alpha/declared-name"

# A manifest with the wrong shape is reported, never a crash. Own directory: a
# sibling worlds.yaml next to it would (correctly, per tier 2) resolve the world
# from there instead, which is a different case, tested separately above.
mkdir -p "$tmp/badmanifest"
printf 'outline: [x]\nworlds: [a, b]\nignore: 3\n' > "$tmp/badmanifest/bad.yaml"
check "malformed manifest" "$(cd "$tmp/myproj" && KB_MANIFEST="$tmp/badmanifest/bad.yaml" bash "$SCRIPT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["world"],d["manifest"],bool(d["manifest_error"]))')" "UNRESOLVED None True"

# Without PyYAML the manifest is reported unreadable and KB_WORLD still works.
mkdir -p "$tmp/noyaml" && echo 'raise ImportError("stub")' > "$tmp/noyaml/yaml.py"
check "no PyYAML" "$(cd "$tmp/myproj" && PYTHONPATH="$tmp/noyaml" KB_WORLD=E bash "$SCRIPT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["world"],d["manifest_error"][:6])')" "E PyYAML"

# --- Cross-manifest / path-root resolution (round 3) ---
# Own directory, so the sibling-manifest glob does not also pick up worlds.yaml /
# single-world.yaml / bad.yaml from the cases above.
cm="$tmp/cm"
mkdir -p "$cm/manifests" "$cm/a/x1" "$cm/a/x2" "$cm/a/ignored-sub" "$cm/a/undeclared" "$cm/b1" "$cm/b2" "$cm/exact-project"
for d in "$cm/a/x1" "$cm/a/x2" "$cm/a/ignored-sub" "$cm/a/undeclared" "$cm/b1" "$cm/b2" "$cm/exact-project"; do
  git -C "$d" init -q && git -C "$d" commit -q --allow-empty -m init
done
cm="$(cd "$cm" && pwd -P)"

# World A's declared repos live under $cm/a (deep, narrow root); World B's live
# directly under $cm (shallow, broad root) -- the real Inkitt-vs-Kolezka shape.
cat > "$cm/manifests/worlds-a.yaml" <<EOF
worlds:
  - name: WorldA
    projects:
      - {name: x1, repo: $cm/a/x1}
      - {name: x2, repo: $cm/a/x2}
ignore:
  - $cm/a/ignored-sub
EOF
cat > "$cm/manifests/worlds-b.yaml" <<EOF
worlds:
  - name: WorldB
    projects:
      - {name: b1, repo: $cm/b1}
      - {name: b2, repo: $cm/b2}
  - name: WorldC
    projects:
      - {name: exact-project, repo: $cm/exact-project}
EOF
# A malformed sibling must not break resolution for the others: it sits in this
# same directory for every case below.
printf 'worlds: [a, b]\n' > "$cm/manifests/worlds-bad.yaml"

# Case 11: an undeclared dir under A's own (deeper) root resolves to A via
# path-root, whichever manifest happens to be active.
out="$(cd "$cm/a/undeclared" && KB_MANIFEST="$cm/manifests/worlds-a.yaml" KB_WORLD='' bash "$SCRIPT")"
check "path-root A (A active)" "$(printf '%s' "$out" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["world"],d["world_source"],d["manifest_error"])')" "WorldA path-root None"
out="$(cd "$cm/a/undeclared" && KB_MANIFEST="$cm/manifests/worlds-b.yaml" KB_WORLD='' bash "$SCRIPT")"
check "path-root A (B active)" "$(printf '%s' "$out" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["world"],d["world_source"])')" "WorldA path-root"

# Case 12: a dir under B's broader root but outside A's resolves to B via
# path-root, whichever manifest is active.
mkdir -p "$cm/y" && git -C "$cm/y" init -q && git -C "$cm/y" commit -q --allow-empty -m init
out="$(cd "$cm/y" && KB_MANIFEST="$cm/manifests/worlds-a.yaml" KB_WORLD='' bash "$SCRIPT")"
check "path-root B (A active)" "$(printf '%s' "$out" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["world"],d["world_source"])')" "WorldB path-root"
out="$(cd "$cm/y" && KB_MANIFEST="$cm/manifests/worlds-b.yaml" KB_WORLD='' bash "$SCRIPT")"
check "path-root B (B active)" "$(printf '%s' "$out" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["world"],d["world_source"])')" "WorldB path-root"

# Case 13: an exact project declared only in the non-active sibling manifest
# still wins, source "manifest", and names which manifest matched.
out="$(cd "$cm/exact-project" && KB_MANIFEST="$cm/manifests/worlds-a.yaml" KB_WORLD='' bash "$SCRIPT")"
check "sibling manifest exact match" "$(printf '%s' "$out" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["world"],d["world_source"],d["manifest_matched"])')" "WorldC manifest $cm/manifests/worlds-b.yaml"

# Case 14: the active manifest's ignore list beats path-root, even for a repo
# that sits inside a declared world's own root.
out="$(cd "$cm/a/ignored-sub" && KB_MANIFEST="$cm/manifests/worlds-a.yaml" KB_WORLD='' bash "$SCRIPT")"
check "ignored beats path-root" "$(printf '%s' "$out" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["world"],d["ignored"])')" "UNRESOLVED True"

# Case 15: a dir outside every declared root stays UNRESOLVED.
mkdir -p "$tmp/cm-outside/proj" && git -C "$tmp/cm-outside/proj" init -q && git -C "$tmp/cm-outside/proj" commit -q --allow-empty -m init
check "outside every root" "$(cd "$tmp/cm-outside/proj" && KB_MANIFEST="$cm/manifests/worlds-a.yaml" KB_WORLD='' bash "$SCRIPT" | field world)" "UNRESOLVED"

# Case 16: two different worlds tied at the same root depth are ambiguous, never
# guessed at. Own directory: this fixture's "same root" shape must not leak into
# the A-vs-B checks above.
tie="$tmp/tie"
mkdir -p "$tie/manifests" "$tie/shared/proj/sub"
git -C "$tie/shared/proj/sub" init -q && git -C "$tie/shared/proj/sub" commit -q --allow-empty -m init
cat > "$tie/manifests/worlds-t.yaml" <<EOF
worlds:
  - name: T1
    projects:
      - {name: t1, repo: $tie/shared/proj}
  - name: T2
    projects:
      - {name: t2, repo: $tie/shared/proj}
EOF
check "equal-depth tie is ambiguous" "$(cd "$tie/shared/proj/sub" && KB_MANIFEST="$tie/manifests/worlds-t.yaml" KB_WORLD='' bash "$SCRIPT" | field world)" "UNRESOLVED"

# Case 17: a directory with no git repo at all resolves project "workspace", never
# the directory's basename.
mkdir -p "$tmp/not-a-repo"
check "non-git project workspace" "$(cd "$tmp/not-a-repo" && KB_MANIFEST="$tmp/none.yaml" bash "$SCRIPT" | field project)" "workspace"

# Invariant: the resolver hardcodes no world name.
if grep -nE "(STX|Inkitt|Kole)" "$ROOT/scripts/resolve_context.py"; then
  echo "FAIL: world name literal in resolve_context.py"; fails=$((fails+1))
fi

[ "$fails" = 0 ] && echo "PASS test_context" || { echo "$fails failure(s)"; exit 1; }
