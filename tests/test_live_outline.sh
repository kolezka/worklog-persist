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
: "${OUTLINE_MCP_URL:?need OUTLINE_MCP_URL for live test (the endpoint .mcp.json references)}"
# Read the endpoint template from .mcp.json and expand it the same way Claude
# Code does, so this test checks the server the plugin actually uses.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mcp_url_template="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["mcpServers"]["outline"]["url"])' "$ROOT/.mcp.json")"
mcp_url="$(python3 -c 'import os,sys;print(os.path.expandvars(sys.argv[1]))' "$mcp_url_template")"
url="${mcp_url%/mcp}"
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
