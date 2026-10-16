#!/usr/bin/env bash
# Off-switch + SessionStart hook gating. Uses an isolated XDG_STATE_HOME so it
# never touches real state. Run: bash tests/test_offswitch.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0
check() { if [ "$2" != "$3" ]; then echo "FAIL: $1 (want '$3', got '$2')"; fails=$((fails+1)); else echo "ok: $1"; fi; }

XDG_STATE_HOME="$(mktemp -d)"
export XDG_STATE_HOME
trap 'rm -rf "$XDG_STATE_HOME"' EXIT
unset WORKLOG_HOOK_OFF || true

check "default on" "$(bash "$ROOT/scripts/persistence-state.sh" status)" "on"

# When on, the hook emits SessionStart JSON carrying the durable-memory rule.
on_out="$(bash "$ROOT/scripts/session-start.sh")"
has_rule="$(printf '%s' "$on_out" | python3 -c "import sys,json;print('Outline (MCP server' in json.load(sys.stdin)['hookSpecificOutput']['additionalContext'])")"
check "hook emits when on" "$has_rule" "True"

# The hook names the resolved KB folder, so the session need not resolve it.
repo="$XDG_STATE_HOME/repo" && mkdir -p "$repo" && git -C "$repo" init -q
has_path="$(cd "$repo" && WORKLOG_CONFIG=/nonexistent WORKLOG_WORLD=W bash "$ROOT/scripts/session-start.sh" \
  | python3 -c "import sys,json;print('\`Worklog/W/repo\`' in json.load(sys.stdin)['hookSpecificOutput']['additionalContext'])")"
check "hook names kb_path" "$has_path" "True"

# When the world is unresolved, the hook states the real cause (here: config error).
has_cause="$(cd "$repo" && WORKLOG_CONFIG=/nonexistent WORKLOG_WORLD='' bash "$ROOT/scripts/session-start.sh" \
  | python3 -c "import sys,json;print('config not found: /nonexistent' in json.load(sys.stdin)['hookSpecificOutput']['additionalContext'])")"
check "hook states unresolved cause" "$has_cause" "True"

# Onboarding: the hook tells the agent to run the setup flow only when the repo
# can be routed by a config entry and is not. Prints: onboarding? cause? path?
ctx() { python3 -c "import sys,json;c=json.load(sys.stdin)['hookSpecificOutput']['additionalContext'];print('onboarding' in c, sys.argv[1] in c, sys.argv[2] in c)" "$1" "$2"; }
hook() { (cd "$repo" && WORKLOG_WORLD="${2:-}" WORKLOG_CONFIG="$1" bash "$ROOT/scripts/session-start.sh"); }
check "onboarding when config missing" "$(hook /nonexistent | ctx 'config not found' 'config file `/nonexistent`')" "True True True"
declared="$XDG_STATE_HOME/declared.yaml"
printf 'worlds:\n  - name: Alpha\n    projects: [{name: elsewhere, repo: /nowhere}]\n' > "$declared"
check "onboarding when repo not declared" "$(hook "$declared" | ctx 'repo not declared' "config file \`$declared\`")" "True True True"
check "no onboarding when resolved" "$(hook "$declared" W | ctx 'Resolved for this repo' '@@none@@')" "False True False"
ignored="$XDG_STATE_HOME/ignored.yaml"
printf 'ignore:\n  - %s\n' "$repo" > "$ignored"
check "no onboarding when ignored" "$(hook "$ignored" | ctx 'no Outline folder' '@@none@@')" "False True False"
# A config that exists but cannot be used is a fix-the-file problem, not onboarding.
broken="$XDG_STATE_HOME/broken.yaml"
printf 'worlds: 3\n' > "$broken"
check "no onboarding when config broken" "$(hook "$broken" | ctx 'config malformed' 'Fix the config file')" "False True True"
# An undeclared repo that sits under a declared world's repos resolves by path
# root, so it is resolved: no onboarding.
ws="$XDG_STATE_HOME/ws"
for d in p1 p2 newrepo; do mkdir -p "$ws/$d" && git -C "$ws/$d" init -q; done
ws="$(cd "$ws" && pwd -P)"
pathroot="$XDG_STATE_HOME/pathroot.yaml"
printf 'worlds:\n  - name: Alpha\n    projects:\n      - {name: p1, repo: %s}\n      - {name: p2, repo: %s}\n' "$ws/p1" "$ws/p2" > "$pathroot"
check "no onboarding when resolved by path-root" \
  "$(cd "$ws/newrepo" && WORKLOG_WORLD='' WORKLOG_CONFIG="$pathroot" bash "$ROOT/scripts/session-start.sh" | ctx 'world `Alpha`' '@@none@@')" "False True False"
# The base reminder text is unchanged in every case.
check "base rule kept when onboarding" "$(hook /nonexistent | ctx 'Outline (MCP server `outline`) is this session' '@@none@@')" "True True False"

bash "$ROOT/scripts/persistence-state.sh" off >/dev/null
check "toggled off" "$(bash "$ROOT/scripts/persistence-state.sh" status)" "off"
check "hook silent when off" "$(bash "$ROOT/scripts/session-start.sh" | wc -c | tr -d ' ')" "0"

bash "$ROOT/scripts/persistence-state.sh" on >/dev/null
check "toggled back on" "$(bash "$ROOT/scripts/persistence-state.sh" status)" "on"

# Env override forces off even without the marker file.
check "env override status" "$(WORKLOG_HOOK_OFF=1 bash "$ROOT/scripts/persistence-state.sh" status)" "off"
check "env override silences hook" "$(WORKLOG_HOOK_OFF=1 bash "$ROOT/scripts/session-start.sh" | wc -c | tr -d ' ')" "0"

[ "$fails" = 0 ] && echo "PASS test_offswitch" || { echo "$fails failure(s)"; exit 1; }
