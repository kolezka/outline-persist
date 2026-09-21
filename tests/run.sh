#!/usr/bin/env bash
# Run the full offline test suite. Real Outline integration stays opt-in and is
# not run here. Usage: bash tests/run.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "== redaction (pytest) =="
python3 -m pytest "$ROOT/tests/test_redact.py" -q

for t in test_context test_offswitch test_structure; do
  echo "== $t =="
  bash "$ROOT/tests/$t.sh"
done

echo "ALL OFFLINE TESTS PASSED"
