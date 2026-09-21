"""Redaction tests with realistic secret-shaped fixtures.

Run: uv run pytest tests/test_redact.py -q   (or: python3 -m pytest)
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "scripts"))

import redact  # noqa: E402

REDACTED = "<REDACTED:"


def _clean(text: str) -> str:
    return redact.redact(text)


def test_bearer_token():
    out = _clean("Authorization: Bearer sk-abc123DEF456ghi789JKL0mno")
    assert "sk-abc123DEF456ghi789JKL0mno" not in out
    assert REDACTED in out


def test_openai_key():
    secret = "sk-proj-ABCDEFGHIJKLMNOPQRSTUV"
    assert secret not in _clean(f"key is {secret} ok")


def test_github_token():
    secret = "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    assert secret not in _clean(f"token {secret}")


def test_aws_access_key():
    assert "AKIAIOSFODNN7EXAMPLE" not in _clean("aws AKIAIOSFODNN7EXAMPLE here")


def test_private_key_block():
    pem = (
        "-----BEGIN RSA PRIVATE KEY-----\n"
        "MIIEowIBAAKCAQEA1234567890abcdef\n"
        "-----END RSA PRIVATE KEY-----"
    )
    out = _clean(f"before\n{pem}\nafter")
    assert "MIIEowIBAAKCAQEA" not in out
    assert "before" in out and "after" in out


def test_generic_named_secret():
    for line in [
        'password = "hunter2secret"',
        "client_secret: 9f8e7d6c5b4a3210",
        "api_key=abcdef0123456789",
        "OUTLINE_API_TOKEN=verysecretvalue123",
    ]:
        out = _clean(line)
        assert REDACTED in out, line


def test_url_password():
    out = _clean("postgres://user:s3cr3tPass@db.host:5432/app")
    assert "s3cr3tPass" not in out
    assert "db.host" in out  # host preserved


def test_polish_nip():
    assert REDACTED in _clean("NIP: 123-456-32-18")
    assert REDACTED in _clean("firma PL1234563218 sp")


def test_iban_and_account():
    assert REDACTED in _clean("IBAN PL61109010140000071219812874")
    assert REDACTED in _clean("konto 61109010140000071219812874")


def test_jwt():
    jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcDEF123456ghiJKL"
    assert jwt not in _clean(f"session {jwt}")


def test_preserves_ordinary_text():
    body = (
        "Objective: migrate outline persistence.\n"
        "Status: active. Branch: feat/outline-persist.\n"
        "Changed files: scripts/redact.py, skills/outline-persist/SKILL.md.\n"
        "Next action: run tests."
    )
    out = _clean(body)
    assert out == body  # no false-positive redactions


def test_idempotent():
    body = "token=abcdef0123456789 and NIP 123-456-32-18"
    once = _clean(body)
    assert _clean(once) == once
