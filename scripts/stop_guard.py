#!/usr/bin/env python3
"""Stop hook for worklog-persist.

Reads the Claude Code Stop-hook JSON on stdin (`session_id`, `transcript_path`,
`cwd`, `stop_hook_active`). When substantive work has happened since the last
Outline write in this transcript, prints `{"decision":"block","reason":...}` so
the model gets one more forced turn to persist state via the worklog-persist
skill. Otherwise prints nothing. Always exits 0: this hook must never crash a
session or turn an internal error into a stuck stop.

Stop fires at the end of every turn, so a decline ("trivial, stopping") must not
be re-blocked forever: each block records the id of the last tool_use it saw, in a
per-session marker file, and later stops only look at tool_uses after that id (or
after the last Outline write, whichever is later). If the marker id is no longer
found in the transcript, it is treated as absent and the hook falls back to the
last write, as if there were no marker at all. The marker is skipped when
`session_id` is missing; a failure to read or write it never breaks the hook.

The transcript is evaluated first, with no subprocess call. `resolve-context.sh`
only runs once the hook has already decided to block, since it is the one part of
this hook slow and fallible enough (kb manifest YAML, subprocess) to be worth not
paying for on every silent turn. If it fails, the hook still blocks, just with a
reason that carries no world context.

Usage: stop_guard.py < stop-hook-input.json
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
WRITE_RE = re.compile(r"^mcp__.*outline.*__(create_document|update_document)$")
# A git subcommand behind any number of `-C <dir>` / `-c key=value` global options,
# or `gh pr create`. `\b...\b(?!-)` so `commit` does not also match `commit-tree`.
_GIT_OPT = r"(?:-C\s+\S+|-c\s+\S+=\S+)"
COMMIT_RE = re.compile(
    rf"\bgit\b(?:\s+{_GIT_OPT})*\s+(?:commit|push)\b(?!-)"
    r"|\bgh\s+pr\s+create\b"
)
EDIT_NAMES = {"Edit", "Write", "NotebookEdit"}
DEFAULT_MIN_TOOLS = 25
SESSION_ID_BAD_CHARS_RE = re.compile(r"[^A-Za-z0-9_-]")


def persistence_is_off():
    r = subprocess.run(
        ["bash", str(HERE / "persistence-state.sh"), "status"],
        capture_output=True, text=True, timeout=10,
    )
    return r.stdout.strip() == "off"


def resolve_context(cwd):
    r = subprocess.run(
        ["bash", str(HERE / "resolve-context.sh")],
        cwd=cwd, capture_output=True, text=True, timeout=10,
    )
    return json.loads(r.stdout)


def load_tool_uses(transcript_path):
    """Ordered (name, input, id) for every non-sidechain assistant tool_use call.

    Unparsable lines are skipped, never fatal: a transcript is append-only JSONL
    that may contain a partial last line.
    """
    tool_uses = []
    with open(transcript_path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if not isinstance(rec, dict) or rec.get("isSidechain") is True:
                continue
            if rec.get("type") != "assistant":
                continue
            content = (rec.get("message") or {}).get("content")
            if not isinstance(content, list):
                continue
            for item in content:
                if isinstance(item, dict) and item.get("type") == "tool_use":
                    tool_uses.append(
                        (item.get("name") or "", item.get("input") or {}, item.get("id"))
                    )
    return tool_uses


def last_write_index(tool_uses):
    """Index of the last Outline write tool_use, or -1 if there was none."""
    last = -1
    for idx, (name, _input, _id) in enumerate(tool_uses):
        if WRITE_RE.match(name):
            last = idx
    return last


def marker_index(tool_uses, marker_id):
    """Index of the tool_use whose id matches the marker, or None if not found."""
    if marker_id is None:
        return None
    for idx, (_name, _input, tid) in enumerate(tool_uses):
        if tid == marker_id:
            return idx
    return None


def state_stop_dir():
    base = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local/state")
    return Path(base) / "worklog-persist" / "stop"


def marker_path(session_id):
    """Path recording the last tool_use id this session was already blocked for.

    None when `session_id` is missing or empty, or sanitizes to nothing: the
    marker feature is skipped rather than guessing at a shared file.
    """
    if not isinstance(session_id, str) or not session_id:
        return None
    sid = SESSION_ID_BAD_CHARS_RE.sub("", session_id)
    return state_stop_dir() / sid if sid else None


def read_marker(session_id):
    """The last tool_use id already shown for this session. None on any failure."""
    path = marker_path(session_id)
    if not path:
        return None
    try:
        raw = path.read_text().strip()
    except OSError:
        return None
    return raw or None


def write_marker(session_id, tool_use_id):
    """Best-effort. A write failure, or a missing id, must never break the hook."""
    path = marker_path(session_id)
    if not path or tool_use_id is None:
        return
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(str(tool_use_id))
    except OSError:
        pass


def is_substantive(subset, min_tools):
    if len(subset) >= min_tools:
        return True
    for name, tool_input, _id in subset:
        if name in EDIT_NAMES:
            return True
        if name == "Bash":
            command = tool_input.get("command")
            if isinstance(command, str) and COMMIT_RE.search(command):
                return True
    return False


def build_reason(identity):
    lead = ("Substantive work has happened since the last Outline write. Run the "
            "worklog-persist skill: checkpoint for ongoing work, handoff if the "
            "session is ending or blocked, or complete if the task is done.")
    trivial = "If the work was trivial and not worth a record, say so in one line and stop."
    if identity is None:
        where = "Context could not be resolved here; the skill resolves the path itself."
        return " ".join([lead, where, trivial])
    world = identity.get("world") or "UNRESOLVED"
    if world == "UNRESOLVED":
        where = ("World is unresolved for this project. Ask the operator once "
                 "which world this belongs to before writing anything.")
    else:
        where = (f"Resolved context: world `{world}`, "
                 f"project `{identity.get('project')}`, "
                 f"tasks path `{identity.get('tasks_path')}`.")
        if identity.get("world_source") == "path-root":
            where += (" (world inferred from the directory; if that is wrong, "
                       "ask the operator)")
    return " ".join([lead, where, trivial])


def run(data):
    if data.get("stop_hook_active"):
        return None
    if persistence_is_off():
        return None

    transcript_path = data.get("transcript_path")
    if not transcript_path or not os.path.isfile(transcript_path):
        return None

    try:
        min_tools = int(os.environ.get("WORKLOG_STOP_MIN_TOOLS") or DEFAULT_MIN_TOOLS)
    except ValueError:
        min_tools = DEFAULT_MIN_TOOLS

    tool_uses = load_tool_uses(transcript_path)
    session_id = data.get("session_id")
    found = marker_index(tool_uses, read_marker(session_id))
    start = max((found + 1) if found is not None else 0, last_write_index(tool_uses) + 1)
    subset = tool_uses[start:]
    if not is_substantive(subset, min_tools):
        return None

    # Only reached when about to block: resolve-context is the slow, fallible part
    # (kb manifest YAML, a subprocess), not worth paying for on every silent turn.
    try:
        identity = resolve_context(data.get("cwd") or ".")
    except Exception:  # noqa: BLE001 - a failed lookup still blocks, just generically
        identity = None
    if identity and identity.get("ignored"):
        return None

    write_marker(session_id, tool_uses[-1][2])
    return {"decision": "block", "reason": build_reason(identity)}


def main():
    try:
        data = json.load(sys.stdin)
        result = run(data)
    except Exception:  # noqa: BLE001 - any internal error must allow the stop
        return 0
    if result:
        print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
