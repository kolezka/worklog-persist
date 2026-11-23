#!/usr/bin/env bash
# SessionStart hook for worklog-persist.
#
# Emits the Outline durable-memory rule as SessionStart additionalContext, so a
# fresh session knows to read prior work state before acting and to checkpoint as
# it goes. Silent no-op when disabled via WORKLOG_HOOK_OFF=1 or the off-state file.
#
# NOTE: plugin SessionStart additionalContext has known delivery bugs in some
# Claude Code builds (anthropics/claude-code #16538, VS Code #88086). The
# worklog-persist SKILL is the robust driver; this hook is best-effort.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if bash "$here/persistence-state.sh" status | grep -q '^off$'; then
  exit 0
fi

read -r -d '' CONTEXT <<'CTX' || true
Outline (MCP server `outline`) is this session's durable work-state store. Use it for multi-step work worth resuming in a later session: read the task record before re-doing captured analysis, and record verified milestones, a handoff when stopping or blocked, and the outcome when done. Small edits, questions and quick fixes need no record, and reads never require a write. Never store secrets, tokens, keys or PII. If the `outline` MCP server is not connected, say persistence is unavailable and carry on. Protocol: the worklog-persist skill or /load, /start, /checkpoint, /handoff, /complete, /dry-run, /off.
CTX

# Best-effort: a resolver failure must never break session start.
IDENTITY="$(bash "$here/resolve-context.sh" 2>/dev/null || true)"

# Emit as JSON via python to keep escaping correct.
python3 - "$CONTEXT" "$IDENTITY" <<'PY'
import json, sys
ctx, identity = sys.argv[1], sys.argv[2]
try:
    i = json.loads(identity)
except ValueError:
    i = None
if i and i.get("kb_path"):
    ctx += (f" Resolved for this repo: world `{i['world']}`, project `{i['project']}`,"
            f" KB folder `{i['kb_path']}`, task records under `{i['tasks_path']}`.")
elif i and i.get("ignored"):
    ctx += (f" Project `{i['project']}` is under `ignore` in the worklog-persist config:"
            " it has no Outline folder. Ask the operator before writing anything for it.")
elif i:
    error = i.get("config_error")
    cause = error or "repo not declared in the worklog-persist config, no WORKLOG_WORLD"
    ctx += (f" World for project `{i['project']}` is unresolved"
            f" ({cause}; config file `{i.get('config_path')}`).")
    # A missing file or a missing entry is onboarding. A file that exists but
    # cannot be used must be fixed first, or /setup would refuse to write it.
    if not error or error.startswith("config not found"):
        ctx += (" When this session first needs to write to Outline,"
                " run the onboarding flow in the worklog-persist skill (/setup): discover the worlds, ask the"
                " user one question, and record the answer with scripts/config-add.sh."
                " Until then, do not interrupt the current task for it.")
    else:
        ctx += (" Fix the config file, or install what the cause names, before writing"
                " anything to Outline. Do not run /setup until it resolves.")
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": ctx,
    }
}))
PY
