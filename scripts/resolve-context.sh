#!/usr/bin/env bash
# Resolve the identity of the current work item, world-agnostically.
#
# Prints JSON with: repo, project, world, branch, worktree, task_slug.
#
# Rules:
#  - Never hardcode a world name. World comes from $KB_WORLD if set, else the
#    sentinel "UNRESOLVED" so the caller resolves it via `kb list` / the manifest
#    or by asking the operator. `kb list` renders a human table (no JSON), so we
#    do not parse it here.
#  - project/repo = basename of `git remote get-url origin` (sans .git), falling
#    back to the repository directory name, matching the outline skill contract.
#  - task_slug = validated kebab-case argument (optional).
set -euo pipefail

slug_arg="${1:-}"

git_top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$git_top" ]; then
  branch="$(git -C "$git_top" rev-parse --abbrev-ref HEAD 2>/dev/null || echo UNKNOWN)"
  worktree="$git_top"
  remote="$(git -C "$git_top" remote get-url origin 2>/dev/null || true)"
  if [ -n "$remote" ]; then
    repo="$(basename "$remote")"
    repo="${repo%.git}"
  else
    repo="$(basename "$git_top")"
  fi
else
  branch="UNKNOWN"
  worktree="$(pwd)"
  repo="$(basename "$(pwd)")"
fi

project="$repo"
world="${KB_WORLD:-UNRESOLVED}"

# Validate the optional slug: lowercase kebab-case only.
task_slug=""
if [ -n "$slug_arg" ]; then
  if printf '%s' "$slug_arg" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'; then
    task_slug="$slug_arg"
  else
    echo "resolve-context.sh: invalid task slug '$slug_arg' (want lowercase kebab-case)" >&2
    exit 2
  fi
fi

python3 - "$repo" "$project" "$world" "$branch" "$worktree" "$task_slug" <<'PY'
import json, sys
repo, project, world, branch, worktree, task_slug = sys.argv[1:7]
print(json.dumps({
    "repo": repo,
    "project": project,
    "world": world,
    "branch": branch,
    "worktree": worktree,
    "task_slug": task_slug,
}))
PY
