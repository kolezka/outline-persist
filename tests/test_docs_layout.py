"""docs/ follows docs/CONVENTIONS.md: the rules marked (tested) there live here."""
import re
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DOCS = REPO / "docs"
FRONT = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)


def _front(doc: Path) -> dict:
    match = FRONT.match(doc.read_text(encoding="utf-8"))
    assert match, f"{doc.relative_to(REPO)} has no front matter"
    out = {}
    for line in match.group(1).splitlines():
        key, _, value = line.partition(":")
        value = value.split(" #")[0].strip()
        if value.startswith("["):
            value = [v.strip() for v in value.strip("[]").split(",") if v.strip()]
        out[key.strip()] = value
    return out


def _docs() -> list[Path]:
    return sorted(DOCS.rglob("*.md"))


def test_front_matter_is_valid_and_pinned_to_one_ancestor_commit():
    pins = set()
    for doc in _docs():
        fm = _front(doc)
        folder = doc.parent.relative_to(DOCS).as_posix()
        assert fm["block"] == ("_root" if folder == "." else folder), doc
        assert fm["doc"] == doc.stem, doc
        pins.add(fm["verified_against"])
    assert len(pins) == 1, f"docs pin more than one commit: {sorted(pins)}"
    pin = pins.pop()
    ancestor = subprocess.run(["git", "merge-base", "--is-ancestor", pin, "HEAD"], cwd=REPO)
    assert ancestor.returncode == 0, f"pin {pin} is not an ancestor of HEAD"


MANDATORY = {"README", "CONTRACTS", "INVARIANTS", "GAPS", "OPERATIONS"}
OPTIONAL = {"DECISIONS"}


def _blocks() -> list[Path]:
    return sorted(p.parent for p in DOCS.rglob("README.md") if p.parent != DOCS)


def test_every_block_has_the_mandatory_file_set():
    blocks = _blocks()
    assert len(blocks) >= 4, f"only {len(blocks)} blocks found; the tree or the glob is gone"
    for block in blocks:
        have = {p.stem for p in block.glob("*.md")}
        missing = MANDATORY - have
        extra = have - MANDATORY - OPTIONAL
        assert not missing, f"{block.relative_to(REPO)} is missing {sorted(missing)}"
        assert not extra, f"{block.relative_to(REPO)} has files outside the set: {sorted(extra)}"


def _tracked() -> list[str]:
    # Untracked-but-not-ignored files count too, so a new file needs an owner
    # before its first commit.
    out = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=REPO, capture_output=True, text=True, check=True,
    ).stdout
    return sorted({p for p in out.split("\0") if p and (REPO / p).exists()})


def _covers(entry: str, path: str) -> bool:
    return path.startswith(entry) if entry.endswith("/") else path == entry


def test_every_tracked_file_has_exactly_one_owner():
    claims = {b.relative_to(DOCS).as_posix(): _front(b / "README.md").get("owns", []) for b in _blocks()}
    claims["unassigned"] = _front(DOCS / "README.md").get("unassigned", [])
    tracked = _tracked()
    assert len(tracked) > 20, f"only {len(tracked)} files listed; git ls-files failed"
    problems = []
    for path in tracked:
        owners = [name for name, entries in claims.items() if any(_covers(e, path) for e in entries)]
        if len(owners) != 1:
            problems.append(f"{path}: owners={owners}")
    for name, entries in claims.items():
        for entry in entries:
            if not any(_covers(entry, p) for p in tracked):
                problems.append(f"{name} claims {entry}, which matches no file")
    assert not problems, "ownership is not a partition:\n" + "\n".join(problems)


CITATION = re.compile(r"`([A-Za-z0-9_./-]+)::([^`]+)`")


def _citation_error(path: str, symbol: str) -> str | None:
    target = REPO / path
    if not target.is_file():
        return f"{path} is not a file"
    text = target.read_text(encoding="utf-8")
    symbol = symbol.strip()
    if symbol.startswith('"'):
        needle = symbol.strip('"')
    else:
        # `Class.method()` and `func()` both reduce to the last name.
        needle = symbol.removesuffix("()").split(".")[-1]
    return None if needle in text else f"{path} does not contain {needle!r}"


def test_every_symbol_citation_resolves():
    broken, checked = [], 0
    for doc in [REPO / "README.md", REPO / "AGENTS.md", *_docs()]:
        for path, symbol in CITATION.findall(doc.read_text(encoding="utf-8")):
            checked += 1
            error = _citation_error(path, symbol)
            if error:
                broken.append(f"{doc.relative_to(REPO)}: `{path}::{symbol}`: {error}")
    # Positive control: a regex that matches nothing passes like a clean tree.
    assert checked > 30, f"only {checked} citations found; the regex or the docs are gone"
    assert not broken, "citations that resolve to nothing:\n" + "\n".join(broken)


LINE_CITATION = re.compile(r"`[A-Za-z0-9_./-]+\.[a-z]+:\d+(?:-\d+)?`")


def test_no_line_number_citations():
    found = []
    for doc in _docs():
        found += [f"{doc.relative_to(REPO)}: {m}" for m in LINE_CITATION.findall(doc.read_text(encoding="utf-8"))]
    assert not found, "cite by symbol, not line number:\n" + "\n".join(found)


LINK = re.compile(r"\]\(([^)\s]+)\)")


def test_every_local_link_resolves():
    broken, checked = [], 0
    for doc in [REPO / "README.md", REPO / "AGENTS.md", *_docs()]:
        for href in LINK.findall(doc.read_text(encoding="utf-8")):
            target = href.split("#")[0]
            if not target or re.match(r"[a-z]+:", target):
                continue
            checked += 1
            if not (doc.parent / target).exists():
                broken.append(f"{doc.relative_to(REPO)} -> {href}")
    assert checked > 10, f"only {checked} local links found; the regex or the docs are gone"
    assert not broken, "links that resolve to nothing:\n" + "\n".join(broken)
