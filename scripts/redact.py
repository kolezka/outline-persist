#!/usr/bin/env python3
"""Redact secret-shaped values from a work-record body before it is written to Outline.

Reads text from stdin (or files given as args) and writes the redacted text to
stdout. Every match is replaced with ``<REDACTED:kind>`` so the shape of the record
is preserved while the secret is removed.

This is a defence-in-depth filter, not a guarantee. The primary rule still holds:
do not put secrets into the record in the first place. The patterns here cover the
realistic shapes named in the plugin contract: bearer/authorization headers, common
API-key formats, private-key blocks, generic ``key=value`` secrets, passwords in
URLs, Polish NIP tax ids, and IBAN / long account numbers.
"""
from __future__ import annotations

import re
import sys

# Each rule: (compiled regex, replacement). Order matters — structured/longer
# patterns run before generic ones so the specific kind wins.
_RULES: list[tuple[re.Pattern[str], str]] = [
    # PEM private key blocks (multiline).
    (
        re.compile(
            r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----",
            re.DOTALL,
        ),
        "<REDACTED:private-key>",
    ),
    # Authorization / bearer header value.
    (
        re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._\-]+"),
        "Bearer <REDACTED:token>",
    ),
    (
        re.compile(r"(?im)^(\s*authorization\s*[:=]\s*).+$"),
        r"\1<REDACTED:authorization>",
    ),
    # Well-known token shapes.
    (re.compile(r"\bsk-[A-Za-z0-9-]{16,}\b"), "<REDACTED:api-key>"),
    (re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}\b"), "<REDACTED:github-token>"),
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"), "<REDACTED:github-token>"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "<REDACTED:aws-access-key-id>"),
    (re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"), "<REDACTED:slack-token>"),
    (re.compile(r"\bAIza[0-9A-Za-z_\-]{20,}\b"), "<REDACTED:google-api-key>"),
    (re.compile(r"\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\b"), "<REDACTED:jwt>"),
    # Generic named secrets: token/secret/password/api_key/client_secret = value.
    (
        re.compile(
            r"(?i)([A-Za-z0-9_]*(?:api[_-]?key|access[_-]?key|secret[_-]?key|client[_-]?secret|"
            r"secret|token|password|passwd|pwd)\s*[:=]\s*)"
            r"(?:\"[^\"]+\"|'[^']+'|[^\s,;}\"']+)"
        ),
        r"\1<REDACTED:secret>",
    ),
    # Password embedded in a URL: scheme://user:password@host
    (
        re.compile(r"(?i)\b([a-z][a-z0-9+.\-]*://[^\s:/@]+:)[^\s@/]+@"),
        r"\1<REDACTED:secret>@",
    ),
    # IBAN (incl. Polish PL + 26 digits) and bare 26-digit account numbers.
    (re.compile(r"\b[A-Z]{2}\d{2}(?:[ ]?[A-Z0-9]){11,30}\b"), "<REDACTED:iban>"),
    (re.compile(r"\b\d{26}\b"), "<REDACTED:account-number>"),
    # Polish NIP tax id: PL-prefixed or 10 digits with common separators.
    (re.compile(r"\bPL\d{10}\b"), "<REDACTED:nip>"),
    (re.compile(r"\b\d{3}[- ]\d{3}[- ]\d{2}[- ]\d{2}\b"), "<REDACTED:nip>"),
    (re.compile(r"\b\d{3}[- ]\d{2}[- ]\d{2}[- ]\d{3}\b"), "<REDACTED:nip>"),
]


def redact(text: str) -> str:
    """Return ``text`` with secret-shaped values replaced by ``<REDACTED:kind>``."""
    for pattern, replacement in _RULES:
        text = pattern.sub(replacement, text)
    return text


def main(argv: list[str]) -> int:
    if argv:
        text = "".join(open(p, encoding="utf-8").read() for p in argv)
    else:
        text = sys.stdin.read()
    sys.stdout.write(redact(text))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
