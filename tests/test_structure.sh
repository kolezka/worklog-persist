#!/usr/bin/env bash
# Plugin discovery + idempotent structure validation + foreign-config safety.
# Run: bash tests/test_structure.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0
note() { echo "$1"; }
fail() { echo "FAIL: $1"; fails=$((fails+1)); }

# 1. --check passes and is idempotent (same result on repeat).
"$ROOT/install.sh" --check >/dev/null || fail "install.sh --check failed"
"$ROOT/install.sh" --check >/dev/null || fail "install.sh --check not idempotent"
note "ok: structure valid and idempotent"

# 2. .mcp.json defines exactly the outline server (reuse, no duplicate, no second client).
servers="$(python3 -c "import json;print(','.join(json.load(open('$ROOT/.mcp.json'))['mcpServers']))")"
[ "$servers" = "outline" ] || fail ".mcp.json servers = '$servers', want 'outline'"
note "ok: single outline MCP server"

# 3. No hardcoded credentials anywhere (only \${ENV} placeholders).
if grep -RInE '(Bearer [A-Za-z0-9]{12,}|CF_ACCESS_CLIENT_SECRET=.+[A-Za-z0-9])' "$ROOT/.mcp.json"; then
  fail "possible hardcoded credential in .mcp.json"
fi
grep -q '${OUTLINE_API_TOKEN}' "$ROOT/.mcp.json" || fail ".mcp.json should use \${OUTLINE_API_TOKEN} placeholder"
note "ok: credentials are env placeholders only"

# 3b. The server URL is an env placeholder too, never one operator's private endpoint.
url="$(python3 -c "import json;print(json.load(open('$ROOT/.mcp.json'))['mcpServers']['outline']['url'])")"
case "$url" in
  '${'*'}') ;;
  *) fail ".mcp.json url is not an \${ENV} placeholder: $url" ;;
esac
if grep -RqiE 'raqz' "$ROOT/.mcp.json"; then
  fail "possible hardcoded operator domain in .mcp.json"
fi
note "ok: server url is an env placeholder, not a hardcoded endpoint"

# 4. hooks.json uses the plugin (wrapped) shape.
python3 -c "import json;h=json.load(open('$ROOT/hooks/hooks.json'));assert h['hooks']['SessionStart']" \
  || fail "hooks.json missing wrapped SessionStart"
note "ok: hooks wrapped"

# 5. hooks.json also wraps Stop, wired to stop-guard.sh, which exists on disk.
python3 -c "import json;h=json.load(open('$ROOT/hooks/hooks.json'));assert h['hooks']['Stop']" \
  || fail "hooks.json missing wrapped Stop"
[ -f "$ROOT/scripts/stop-guard.sh" ] || fail "missing scripts/stop-guard.sh"
[ -f "$ROOT/scripts/stop_guard.py" ] || fail "missing scripts/stop_guard.py"
note "ok: Stop hook wired to stop-guard.sh"

# 6. All 8 verbs exist as commands.
for c in load start checkpoint handoff complete dry-run off setup; do
  [ -f "$ROOT/commands/$c.md" ] || fail "missing command: $c"
done
note "ok: all 8 verb commands present"

# 7. The skill names both MCP tool prefixes and pins neither one. A plugin-only
# install exposes mcp__plugin_worklog-persist_outline__*, never mcp__outline__*.
skill="${SKILL_FILE:-$ROOT/skills/worklog-persist/SKILL.md}"
grep -q 'mcp__plugin_worklog-persist_outline__' "$skill" || fail "skill omits the plugin-scoped tool prefix"
if grep -q 'select:mcp__outline__' "$skill"; then fail "skill hardcodes the user-scope tool prefix"; fi
note "ok: skill handles both MCP tool prefixes"

# 8. No operator-identifying string anywhere in the tracked tree. The pattern is
# split across two literals so this line itself never matches its own check.
private_pattern='ra''qz'
hits="$(cd "$ROOT" && git grep -liE "$private_pattern" -- . ":(exclude)tests/test_structure.sh" 2>/dev/null || true)"
[ -z "$hits" ] || fail "operator-identifying string found in: $hits"
note "ok: no operator-identifying strings in tracked tree"

[ "$fails" = 0 ] && echo "PASS test_structure" || { echo "$fails failure(s)"; exit 1; }
