#!/usr/bin/env bash
# Resolve the identity and Outline address of the current work item.
# Thin wrapper: the logic lives in resolve_context.py (it has to parse the kb
# manifest YAML). Usage: resolve-context.sh [task-slug]
set -euo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve_context.py" "$@"
