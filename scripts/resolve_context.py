#!/usr/bin/env python3
"""Resolve the identity and Outline address of the current work item.

Prints JSON. The KB structure follows the dotfiles-next `kb` manifest
(`$KB_MANIFEST`, else ~/.config/kb/worlds.yaml): collections come from its
`outline:` block, and a repo declared under `worlds[].projects[]` gets its world,
project name and optional `kb_folder` from there. No world name is hardcoded.

World precedence: (1) project match in the active manifest; (2) project match in
any OTHER `worlds*.yaml` sibling of the active manifest's path (default
~/.config/kb); (3) $KB_WORLD; (4) path root, the world whose declared repos'
common ancestor is the deepest ancestor-or-equal of the current repo (a tie
between different worlds at the same depth is ambiguous); (5) "UNRESOLVED" (the
caller asks the operator once). The active manifest is picked by which env
launched the session ($KB_MANIFEST), not by cwd, so tier 4 exists because that
alone is not enough to place a path correctly: a path under a world's own repos
should resolve to that world even when a different world's manifest is active.
An ignored repo (the active manifest's `ignore:` list) gets no world from tiers
3 or 4 either. Usage: resolve_context.py [task-slug]
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

UNRESOLVED = "UNRESOLVED"
# Plain kebab slug, or a ticket-prefixed one (AD-163-uat-checklist).
SLUG_RE = re.compile(r"^(?:[A-Z][A-Z0-9]*-[0-9]+-)?[a-z0-9]+(?:-[a-z0-9]+)*$")
# Used only when no manifest is readable; the manifest always wins.
DEFAULT_OUTLINE = {
    "root_collection": "raqz.pl",
    "global_collection": "Claude's Notebook",
    "archive_collection": "Archive",
}


def git(*args, cwd):
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def canonical_repo(cwd):
    """Main checkout of the repo, so a linked worktree maps to its real project."""
    top = git("rev-parse", "--show-toplevel", cwd=cwd)
    if not top:
        return None, None
    git_dir = git("rev-parse", "--absolute-git-dir", cwd=cwd)
    common = git("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=cwd)
    main = Path(top)
    if git_dir and common and Path(git_dir).resolve() != Path(common).resolve():
        # Linked worktree: the first `git worktree list` record is the main checkout.
        first = git("worktree", "list", "--porcelain", cwd=cwd).split("\n", 1)[0]
        if first.startswith("worktree "):
            main = Path(first[len("worktree "):])
    return Path(top), main.resolve()


def manifest_path():
    return Path(os.environ.get("KB_MANIFEST") or Path.home() / ".config/kb/worlds.yaml")


def load_manifest(path):
    """Return (manifest dict or None, error string or None). Never raises."""
    if not path.is_file():
        return None, f"manifest not found: {path}"
    try:
        import yaml
    except ImportError:
        return None, "PyYAML not installed; cannot read the kb manifest"
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception as e:  # noqa: BLE001 - report, the caller decides
        return None, f"manifest unreadable: {e}"
    error = shape_error(data)
    return (None, f"manifest malformed: {error}") if error else (data, None)


def shape_error(data):
    """Check only the shape this script reads, so a bad manifest cannot crash it."""
    if not isinstance(data, dict):
        return "not a mapping"
    if not isinstance(data.get("outline") or {}, dict):
        return "`outline` is not a mapping"
    worlds = data.get("worlds") or []
    if not isinstance(worlds, list) or not all(isinstance(w, dict) for w in worlds):
        return "`worlds` is not a list of mappings"
    for w in worlds:
        projects = w.get("projects") or []
        if not isinstance(projects, list) or not all(isinstance(x, dict) for x in projects):
            return f"world {w.get('name')!r}: `projects` is not a list of mappings"
    if not isinstance(data.get("ignore") or [], list):
        return "`ignore` is not a list"
    return None


def expand(p):
    """Absolute real path, or None when it cannot be expanded (e.g. `~nouser`)."""
    try:
        return Path(str(p)).expanduser().resolve()
    except (OSError, RuntimeError):
        return None


def find_project(manifest, repo):
    for w in manifest.get("worlds") or []:
        for p in w.get("projects") or []:
            if p.get("repo") and expand(p["repo"]) == repo:
                return w.get("name"), p
    return None, None


def sibling_manifests(active_path, active_manifest):
    """[(resolved path, manifest dict), ...] for every worlds*.yaml next to the
    active manifest (its own directory, default ~/.config/kb), plus the active
    one itself, deduped by resolved path. Malformed or unreadable siblings are
    skipped silently: this is best-effort cross-manifest context, not a
    load-bearing file, and one bad sibling must never break resolution.
    """
    found = []
    seen = set()
    active_key = expand(active_path)
    if active_manifest and active_key:
        found.append((active_key, active_manifest))
        seen.add(active_key)
    try:
        candidates = sorted(active_path.parent.glob("worlds*.yaml"))
    except OSError:
        candidates = []
    for c in candidates:
        key = expand(c)
        if not key or key in seen:
            continue
        seen.add(key)
        data, _err = load_manifest(key)
        if data:
            found.append((key, data))
    return found


def world_repo_roots(manifests):
    """{world name: common ancestor of its declared, expanded repo paths}.

    Pools repos declared for the same world name across different manifest
    files. A world with no repos anywhere contributes no root.
    """
    repos_by_world = {}
    for _path, data in manifests:
        for w in data.get("worlds") or []:
            name = w.get("name")
            if not name:
                continue
            for p in w.get("projects") or []:
                rp = expand(p.get("repo")) if p.get("repo") else None
                if rp:
                    repos_by_world.setdefault(name, []).append(rp)
    roots = {}
    for name, paths in repos_by_world.items():
        try:
            roots[name] = Path(os.path.commonpath([str(p) for p in paths]))
        except ValueError:
            continue  # e.g. paths on different drives; not a usable root
    return roots


def path_root_world(roots, target):
    """The world whose root is the deepest ancestor-or-equal of `target`.

    None both when nothing qualifies and when two or more different-named
    roots tie for the deepest match (ambiguous, left to another tier).
    """
    matches = [(len(root.parts), name) for name, root in roots.items()
               if root == target or root in target.parents]
    if not matches:
        return None
    best_depth = max(depth for depth, _name in matches)
    tied = {name for depth, name in matches if depth == best_depth}
    return tied.pop() if len(tied) == 1 else None


def main(argv):
    slug = argv[1] if len(argv) > 1 else ""
    if slug and not SLUG_RE.match(slug):
        print(f"resolve-context: invalid task slug '{slug}' "
              "(want kebab-case, optionally TICKET-123- prefixed)", file=sys.stderr)
        return 2

    cwd = Path.cwd()
    worktree, repo_root = canonical_repo(cwd)
    is_git = worktree is not None
    if worktree:
        branch = git("rev-parse", "--abbrev-ref", "HEAD", cwd=worktree) or "UNKNOWN"
        remote = git("remote", "get-url", "origin", cwd=worktree)
    else:
        worktree, repo_root, branch, remote = cwd, cwd.resolve(), "UNKNOWN", ""
    repo = re.sub(r"\.git$", "", remote.rstrip("/").rsplit("/", 1)[-1].rsplit(":", 1)[-1]) \
        if remote else repo_root.name

    mpath = manifest_path()
    manifest, manifest_error = load_manifest(mpath)
    outline = dict(DEFAULT_OUTLINE)
    if manifest:
        outline.update({k: v for k, v in (manifest.get("outline") or {}).items()
                        if k in DEFAULT_OUTLINE and v})

    all_manifests = sibling_manifests(mpath, manifest)
    active_key = expand(mpath)

    world, project, kb_folder, source, matched_manifest = (
        None, (repo if is_git else "workspace"), None, "fallback", None
    )
    ignored = False
    if manifest:
        w, p = find_project(manifest, repo_root)
        if p:
            world, project, kb_folder, source = w, p.get("name") or repo, p.get("kb_folder"), "manifest"
            matched_manifest = str(active_key)
        ignored = any(i and (i == repo_root or i in repo_root.parents)
                      for i in map(expand, manifest.get("ignore") or []))
    # Tier 2: an exact declaration in a sibling manifest is as explicit as tier 1,
    # so (like tier 1) it wins regardless of an ignore note in the active one.
    if not world:
        for path, data in all_manifests:
            if path == active_key:
                continue
            w, p = find_project(data, repo_root)
            if p:
                world, project, kb_folder, source = w, p.get("name") or repo, p.get("kb_folder"), "manifest"
                matched_manifest = str(path)
                break
    # An ignored repo has no Outline folder by operator decision; inference
    # (env, path root) must not add one. An explicit declaration (above) still can.
    if not world and not ignored and os.environ.get("KB_WORLD"):
        world, source = os.environ["KB_WORLD"], "env"
    # Tier 4: which declared world's repos this one sits under, deepest wins. This
    # is what makes resolution depend on the path, not on which manifest happened
    # to be active when the session started.
    if not world and not ignored and all_manifests:
        target = repo_root if is_git else cwd.resolve()
        w = path_root_world(world_repo_roots(all_manifests), target)
        if w:
            world, source = w, "path-root"
    world = world or UNRESOLVED

    candidate_worlds = []
    seen_names = set()
    for _path, data in all_manifests:
        for w in data.get("worlds") or []:
            name = w.get("name")
            if name and name not in seen_names:
                seen_names.add(name)
                candidate_worlds.append(name)

    root = outline["root_collection"]
    kb_path = kb_folder or (f"{root}/{world}/{project}" if world != UNRESOLVED else None)
    mirror_root = Path(os.environ.get("OUTLINE_ROOT") or Path.home() / "Development/outline-kb") / "outline-sync"
    # The mirror drops the root-collection segment: outline-sync/<World>/<project>.
    mirror_dir = None
    if kb_path and kb_path.startswith(root + "/"):
        candidate = mirror_root / kb_path[len(root) + 1:]
        mirror_dir = str(candidate) if candidate.is_dir() else None

    print(json.dumps({
        "repo": repo,
        "repo_root": str(repo_root),
        "project": project,
        "world": world,
        "world_source": source,
        "manifest_matched": matched_manifest,
        "candidate_worlds": candidate_worlds,
        "ignored": ignored,
        "branch": branch,
        "worktree": str(worktree),
        "task_slug": slug,
        "root_collection": root,
        "global_collection": outline["global_collection"],
        "archive_collection": outline["archive_collection"],
        "kb_path": kb_path,
        "tasks_path": f"{kb_path}/Tasks" if kb_path else None,
        "record_path": f"{kb_path}/Tasks/{slug}" if kb_path and slug else None,
        "mirror_dir": mirror_dir,
        "manifest": str(mpath) if manifest else None,
        "manifest_error": manifest_error,
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
