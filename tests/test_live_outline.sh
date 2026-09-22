#!/usr/bin/env bash
# OPT-IN real Outline integration smoke test. Skipped unless WORKLOG_PERSIST_LIVE=1
# and the outline MCP env is present. Never required in CI; never needs creds by
# default. This only checks reachability of the configured Outline endpoint; it
# does NOT create or mutate documents.
set -euo pipefail

if [ "${WORKLOG_PERSIST_LIVE:-}" != 1 ]; then
  echo "SKIP: set WORKLOG_PERSIST_LIVE=1 to run the live Outline reachability check"
  exit 0
fi

: "${OUTLINE_API_TOKEN:?need OUTLINE_API_TOKEN for live test}"
url="https://outline.raqz.link"
code="$(curl -s -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer ${OUTLINE_API_TOKEN}" \
  ${CF_ACCESS_CLIENT_ID:+-H "CF-Access-Client-Id: ${CF_ACCESS_CLIENT_ID}"} \
  ${CF_ACCESS_CLIENT_SECRET:+-H "CF-Access-Client-Secret: ${CF_ACCESS_CLIENT_SECRET}"} \
  "$url/api/auth.info" -X POST || echo 000)"

if [ "$code" = 200 ]; then
  echo "PASS: Outline reachable and authenticated ($code)"
else
  echo "FAIL: Outline returned HTTP $code (check env / access)"; exit 1
fi
