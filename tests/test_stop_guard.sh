#!/usr/bin/env bash
# Stop-hook tests for scripts/stop-guard.sh. Uses an isolated XDG_STATE_HOME and
# WORKLOG_CONFIG so it never touches real state. Run: bash tests/test_stop_guard.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/stop-guard.sh"
fails=0
check() { if [ "$2" != "$3" ]; then echo "FAIL: $1 (want '$3', got '$2')"; fails=$((fails+1)); else echo "ok: $1"; fi; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

XDG_STATE_HOME="$tmp/state"
export XDG_STATE_HOME
mkdir -p "$XDG_STATE_HOME"
unset WORKLOG_HOOK_OFF WORKLOG_STOP_MIN_TOOLS WORKLOG_STOP_MIN_EDITS WORKLOG_STOP_COOLDOWN_MIN WORKLOG_WORLD || true
# Claude Code sets these in every hook's environment. Clear them so a run from
# inside `claude -p` behaves like a run from a plain terminal.
unset CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CODE_ENTRYPOINT || true
# Isolate from the host config so world resolution stays deterministic.
export WORKLOG_CONFIG="$tmp/none.yaml"

cwd_dir="$tmp/work"
mkdir -p "$cwd_dir"

# Build the Stop-hook stdin JSON for a given transcript file. Session id
# defaults to "s1", the fixed id used by every case that predates the marker.
input() {
  python3 -c '
import json, sys
print(json.dumps({
    "session_id": sys.argv[4],
    "transcript_path": sys.argv[1],
    "cwd": sys.argv[2],
    "stop_hook_active": sys.argv[3] == "true",
}))
' "$1" "$2" "$3" "${4:-s1}"
}

decision() {
  # Reads stop-guard stdout; prints the "decision" field, or "" for empty/no output.
  python3 -c '
import json, sys
raw = sys.stdin.read().strip()
if not raw:
    print("")
else:
    print(json.loads(raw).get("decision", ""))
'
}

# Env assignments in front of a run_guard call reach the hook process.
run_guard() {
  local transcript="$1" active="${2:-false}" session="${3:-s1}"
  input "$transcript" "$cwd_dir" "$active" "$session" | bash "$SCRIPT"
}

# Transcript lines. Each prints one assistant record holding one tool_use.
edit_line() {
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"%s","name":"Edit","input":{"file_path":"a.py"}}]}}\n' "$1"
}
commit_line() {
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"%s","name":"Bash","input":{"command":"git commit -m x"}}]}}\n' "$1"
}
# One Bash tool_use with id $1 running command $2 (no quotes or backslashes in $2).
bash_line() {
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"%s","name":"Bash","input":{"command":"%s"}}]}}\n' "$1" "$2"
}
# $1 Edit lines, with ids <$2>-1 .. <$2>-$1.
edits() {
  local i
  for i in $(seq 1 "$1"); do edit_line "$2-$i"; done
}
# An Outline write made $1 minutes ago, stamped the way Claude Code stamps records.
write_line() {
  python3 -c '
import datetime, json, sys
ts = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=float(sys.argv[1]))
print(json.dumps({
    "type": "assistant",
    "timestamp": ts.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
    "message": {"content": [{"type": "tool_use", "id": "w-" + sys.argv[1],
                             "name": "mcp__outline__update_document", "input": {}}]},
}))
' "$1"
}
# Backdate a session's marker by $2 minutes, as if its last block was that long ago.
# The marker path comes from the hook itself, not restated here.
age_marker() {
  python3 -c "
import os, sys, time
sys.path.insert(0, '$ROOT/scripts')
import stop_guard as m
t = time.time() - float(sys.argv[2]) * 60
os.utime(m.marker_path(sys.argv[1]), (t, t))
" "$1" "$2"
}

# Fixture: no tool_use at all.
t_no_work="$tmp/no_work.jsonl"
cat > "$t_no_work" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"hello"}]}}
EOF

# Fixture: one Edit, no Outline write ever.
t_edit_no_write="$tmp/edit_no_write.jsonl"
edit_line "tu-one" > "$t_edit_no_write"

# Fixture: a long run of edits with no commit, push, PR or release.
t_edits_many="$tmp/edits_many.jsonl"
edits 40 em > "$t_edits_many"

# Fixture: a long read-only run, including Bash commands that only read.
t_reads_many="$tmp/reads_many.jsonl"
{
  for i in $(seq 1 60); do
    printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"rd-%s","name":"Read","input":{}}]}}\n' "$i"
  done
  bash_line "rd-log" "git log --oneline -5"
  bash_line "rd-status" "git status"
  bash_line "rd-prview" "gh pr view 12"
} > "$t_reads_many"

# Fixture: a commit, no Outline write ever.
t_commit="$tmp/commit.jsonl"
commit_line "tu-commit" > "$t_commit"

# Fixture: a commit, then a user-scope Outline update_document.
t_edit_then_write="$tmp/edit_then_write.jsonl"
{ edits 5 ew; commit_line "ew-commit"; printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__outline__update_document","input":{}}]}}'; } > "$t_edit_then_write"

# Fixture: the same blocking work, but done on subagent (sidechain) transcript lines.
t_sidechain="$tmp/sidechain.jsonl"
{ edits 5 sc; commit_line "sc-commit"; } | sed 's/"type":"assistant"/"type":"assistant","isSidechain":true/' > "$t_sidechain"

# Fixture: a commit, then a plugin-scoped Outline write (not the bare mcp__outline__ prefix).
t_plugin_write="$tmp/plugin_write.jsonl"
{ edits 5 pw; commit_line "pw-commit"; printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__plugin_worklog-persist_outline__create_document","input":{}}]}}'; } > "$t_plugin_write"

# Fixture: unparsable content, must never crash the hook.
t_garbage="$tmp/garbage.jsonl"
cat > "$t_garbage" <<'EOF'
not json at all {{{
{"type":"assistant","message":
EOF

# Each case below uses its own session id: these fixtures are independent
# hypothetical sessions, and giving them distinct ids keeps one case's marker
# from leaking into another's (the marker cases further down test the sharing
# deliberately, with explicit shared/distinct ids of their own).

# Case 1: no substantive work at all -> allow, silent.
out="$(run_guard "$t_no_work" false "case1")"
check "no work: silent" "$out" ""

# Case 2: a single Edit is not substantive on its own -> allow.
out="$(run_guard "$t_edit_no_write" false "case2")"
check "one edit: silent" "$out" ""

# Case 2a: edits alone never block, however many there are.
out="$(run_guard "$t_edits_many" false "case2a")"
check "edits only: silent" "$out" ""

# Case 2b: a long read-only run never blocks, read-only git/gh commands included.
out="$(run_guard "$t_reads_many" false "case2b")"
check "long read-only run: silent" "$out" ""

# Case 2c: the old edit/tool-count knobs no longer force a block.
out="$(WORKLOG_STOP_MIN_EDITS=1 WORKLOG_STOP_MIN_TOOLS=1 run_guard "$t_edits_many" false "case2c")"
check "legacy count knobs: silent" "$out" ""

# Case 2e: each shipping command blocks on its own, after edits or not.
ship_case() {
  local name="$1" cmd="$2" f="$tmp/ship_$3.jsonl"
  { edits 2 "sh$3"; bash_line "sh$3-cmd" "$cmd"; } > "$f"
  check "$name" "$(run_guard "$f" false "ship-$3" | decision)" "block"
}
ship_case "push: decision" "git push -u origin feat/x" push
ship_case "pr create: decision" "gh pr create --title x --body y" prc
ship_case "pr merge: decision" "gh pr merge 12 --squash" prm
ship_case "release: decision" "gh release create v1.2.3" rel
ship_case "publish: decision" "pnpm publish --access public" pub
ship_case "deploy: decision" "fly deploy" dep

# Case 2d: a commit blocks on its own, with no edits at all.
out="$(run_guard "$t_commit" false "case2d")"
check "commit: decision" "$(printf '%s' "$out" | decision)" "block"
check "commit: mentions checkpoint" "$(printf '%s' "$out" | grep -c 'worklog-persist skill')" "1"
# The work dir is not declared anywhere, so the reason sends the model to onboarding.
check "unresolved: reason points to /setup" \
  "$(printf '%s' "$out" | python3 -c 'import json,sys; r=json.load(sys.stdin)["reason"]; print("/setup" in r, "Ask the operator once" in r)')" "True False"

# Case 3: an Outline write after the edits clears the slate -> allow.
out="$(run_guard "$t_edit_then_write" false "case3")"
check "edit then write: silent" "$out" ""

# Case 4: stop_hook_active=true always allows, even with unpersisted work.
out="$(run_guard "$t_commit" true "case4")"
check "stop_hook_active: silent" "$out" ""

# Case 5: persistence off (WORKLOG_HOOK_OFF=1) always allows.
out="$(WORKLOG_HOOK_OFF=1 run_guard "$t_commit" false "case5")"
check "persistence off: silent" "$out" ""

# Case 6: the only work is on sidechain (subagent) lines -> ignored -> allow.
out="$(run_guard "$t_sidechain" false "case6")"
check "sidechain only: silent" "$out" ""

# Case 7: a plugin-prefixed Outline write counts as a write, clearing the slate.
out="$(run_guard "$t_plugin_write" false "case7")"
check "plugin-prefixed write: silent" "$out" ""

# Case 8: a garbage transcript must never crash the hook; unparsable lines are
# skipped, so with no real tool_use found the result is a silent allow.
out="$(run_guard "$t_garbage" false "case8")"
check "garbage transcript: silent" "$out" ""
rc=0; run_guard "$t_garbage" false "case8" >/dev/null 2>&1 || rc=$?
check "garbage transcript: exit 0" "$rc" "0"

# The marker cases below re-stop the same session back to back, so they turn the
# cooldown off (WORKLOG_STOP_COOLDOWN_MIN=0) to test the marker on its own.

# Fixture dedicated to the per-session decline marker below. Mutated in place
# by case 11, so it is kept separate from the fixed transcripts used above. The
# marker stores a tool_use id, so these fixtures need real ids.
t_marker="$tmp/marker.jsonl"
commit_line "tu-a1" > "$t_marker"

# Case 10: a block is recorded for this session; the same transcript, not
# extended further, does not re-block the next stop (a decline is honoured
# once the work behind it has actually been shown).
out="$(WORKLOG_STOP_COOLDOWN_MIN=0 run_guard "$t_marker" false "sess-a")"
check "marker: first block" "$(printf '%s' "$out" | decision)" "block"
out="$(WORKLOG_STOP_COOLDOWN_MIN=0 run_guard "$t_marker" false "sess-a")"
check "marker: declined work not re-nagged" "$out" ""

# Case 11: new work appended after the decline blocks again, same session.
commit_line "tu-a2" >> "$t_marker"
out="$(WORKLOG_STOP_COOLDOWN_MIN=0 run_guard "$t_marker" false "sess-a")"
check "marker: new work after decline blocks again" "$(printf '%s' "$out" | decision)" "block"

# Case 12: a different session has no marker of its own, so the same
# transcript still blocks for it even though sess-a just saw this work.
out="$(WORKLOG_STOP_COOLDOWN_MIN=0 run_guard "$t_marker" false "sess-b")"
check "marker: different session still blocks" "$(printf '%s' "$out" | decision)" "block"

# Case 13: a recorded marker id that no longer appears in the transcript is
# treated as absent (falls back to the last write) rather than trusting a
# stale marker forever or blocking on every single turn regardless of id.
t_missing_a="$tmp/marker_missing_a.jsonl"
commit_line "tu-x" > "$t_missing_a"
out="$(WORKLOG_STOP_COOLDOWN_MIN=0 run_guard "$t_missing_a" false "sess-c")"
check "marker: setup block to record tu-x for sess-c" "$(printf '%s' "$out" | decision)" "block"

t_missing_b="$tmp/marker_missing_b.jsonl"
commit_line "tu-z" > "$t_missing_b"
out="$(WORKLOG_STOP_COOLDOWN_MIN=0 run_guard "$t_missing_b" false "sess-c")"
check "marker: id missing from transcript falls back and blocks" "$(printf '%s' "$out" | decision)" "block"

# Case 14: a second shipping stop inside the default cooldown (90 min) after a
# block is allowed; once the last block is older than that, it blocks again.
t_cool="$tmp/cooldown.jsonl"
commit_line "tu-c1" > "$t_cool"
out="$(run_guard "$t_cool" false "sess-cool")"
check "cooldown: first block" "$(printf '%s' "$out" | decision)" "block"
commit_line "tu-c2" >> "$t_cool"
out="$(run_guard "$t_cool" false "sess-cool")"
check "cooldown: new work inside cooldown is silent" "$out" ""
age_marker "sess-cool" 31
out="$(run_guard "$t_cool" false "sess-cool")"
check "cooldown: default is 90 minutes, not 30" "$out" ""
age_marker "sess-cool" 91
out="$(run_guard "$t_cool" false "sess-cool")"
check "cooldown: new work after cooldown blocks" "$(printf '%s' "$out" | decision)" "block"

# Case 14b: WORKLOG_STOP_COOLDOWN_MIN still overrides the default.
t_cool_env="$tmp/cooldown_env.jsonl"
commit_line "tu-ce1" > "$t_cool_env"
run_guard "$t_cool_env" false "sess-cool-env" >/dev/null
commit_line "tu-ce2" >> "$t_cool_env"
age_marker "sess-cool-env" 31
out="$(WORKLOG_STOP_COOLDOWN_MIN=30 run_guard "$t_cool_env" false "sess-cool-env")"
check "cooldown: env override shortens it" "$(printf '%s' "$out" | decision)" "block"

# Case 15: an Outline write starts the same cooldown as a block does.
t_recent_write="$tmp/recent_write.jsonl"
{ write_line 5; commit_line "tu-rw"; } > "$t_recent_write"
out="$(run_guard "$t_recent_write" false "case15-recent")"
check "cooldown: work 5 min after a write is silent" "$out" ""
t_old_write="$tmp/old_write.jsonl"
{ write_line 40; commit_line "tu-ow"; } > "$t_old_write"
out="$(run_guard "$t_old_write" false "case15-mid")"
check "cooldown: work 40 min after a write is silent" "$out" ""
{ write_line 100; commit_line "tu-ow"; } > "$t_old_write"
out="$(run_guard "$t_old_write" false "case15-old")"
check "cooldown: work 100 min after a write blocks" "$(printf '%s' "$out" | decision)" "block"
# A write stamped ahead of the clock must not mute the guard until then.
t_future_write="$tmp/future_write.jsonl"
{ write_line -60; commit_line "tu-fw"; } > "$t_future_write"
out="$(run_guard "$t_future_write" false "case15-future")"
check "cooldown: write stamped in the future is ignored" "$(printf '%s' "$out" | decision)" "block"

# Case 16: nobody is watching a non-interactive session, so it never blocks.
# CLAUDE_CODE_SESSION_ATTENDED decides when set; CLAUDE_CODE_ENTRYPOINT otherwise.
out="$(CLAUDE_CODE_SESSION_ATTENDED=0 CLAUDE_CODE_ENTRYPOINT=sdk-cli run_guard "$t_commit" false "case16-print")"
check "unattended: claude -p env is silent" "$out" ""
out="$(CLAUDE_CODE_ENTRYPOINT=sdk-ts run_guard "$t_commit" false "case16-sdk")"
check "unattended: sdk entrypoint without attended flag is silent" "$out" ""
out="$(CLAUDE_CODE_SESSION_ATTENDED=1 CLAUDE_CODE_ENTRYPOINT=cli run_guard "$t_commit" false "case16-tui")"
check "attended: interactive env still blocks" "$(printf '%s' "$out" | decision)" "block"
out="$(CLAUDE_CODE_SESSION_ATTENDED=1 CLAUDE_CODE_ENTRYPOINT=sdk-cli run_guard "$t_commit" false "case16-flag")"
check "attended: flag wins over entrypoint" "$(printf '%s' "$out" | decision)" "block"

# Case 17: a block the marker cannot record would repeat on every stop, so the
# hook allows instead: no tool_use id to record, or a state dir it cannot write.
t_no_id="$tmp/no_id.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git commit -m x"}}]}}' > "$t_no_id"
out="$(run_guard "$t_no_id" false "case17-noid")"
check "unrecordable: no tool_use id is silent" "$out" ""
: > "$tmp/state-is-a-file"
out="$(XDG_STATE_HOME="$tmp/state-is-a-file" run_guard "$t_commit" false "case17-unwritable")"
check "unrecordable: unwritable state dir is silent" "$out" ""

# SHIP_RE unit cases: a git subcommand behind -C/-c global options is still
# caught, a lookalike subcommand (commit-tree) is not, and PR, release, publish
# and deploy commands count while read-only lookalikes do not.
commit_re() {
  python3 -c "
import sys
sys.path.insert(0, '$ROOT/scripts')
import stop_guard as m
print(bool(m.SHIP_RE.search(sys.argv[1])))
" "$1"
}
check "SHIP_RE: plain commit" "$(commit_re 'git commit -m x')" "True"
check "SHIP_RE: plain push" "$(commit_re 'git push origin main')" "True"
check "SHIP_RE: -C option before commit" "$(commit_re 'git -C /repo commit -m x')" "True"
check "SHIP_RE: -c option before commit" "$(commit_re 'git -c user.email=a@b commit')" "True"
check "SHIP_RE: commit-tree is not commit" "$(commit_re 'git commit-tree -m x')" "False"
check "SHIP_RE: unrelated git command" "$(commit_re 'git checkout -- file')" "False"
check "SHIP_RE: gh pr create" "$(commit_re 'gh pr create --title x')" "True"
check "SHIP_RE: chained -C and -c before push" \
  "$(commit_re 'git -C /repo -c user.name=a push')" "True"
check "SHIP_RE: gh pr merge" "$(commit_re 'gh pr merge 3 --squash')" "True"
check "SHIP_RE: gh pr view is not shipping" "$(commit_re 'gh pr view 3')" "False"
check "SHIP_RE: gh release create" "$(commit_re 'gh release create v1')" "True"
check "SHIP_RE: npm publish" "$(commit_re 'npm publish')" "True"
check "SHIP_RE: uv publish" "$(commit_re 'uv publish')" "True"
check "SHIP_RE: make release" "$(commit_re 'make release')" "True"
check "SHIP_RE: deploy script" "$(commit_re './scripts/deploy.sh prod')" "True"
check "SHIP_RE: vercel deploy" "$(commit_re 'vercel deploy --prod')" "True"
check "SHIP_RE: searching for the word deploy" "$(commit_re 'rg -n deploy docs')" "False"
check "SHIP_RE: git log" "$(commit_re 'git log --oneline')" "False"

# Case: resolve-context.sh failing outright (not just returning UNRESOLVED) still
# blocks, with a generic reason that makes no world claim. Uses a copy of scripts/
# with a broken resolve-context.sh; everything else (persistence-state.sh, the
# hook itself) is the real, unmodified script.
broken="$tmp/broken-scripts"
mkdir -p "$broken"
cp "$ROOT"/scripts/*.sh "$ROOT"/scripts/*.py "$broken"/
printf '#!/usr/bin/env bash\nexit 1\n' > "$broken/resolve-context.sh"
t_broken="$tmp/broken_ctx.jsonl"
commit_line "tu-broken" > "$t_broken"
out="$(input "$t_broken" "$cwd_dir" false "sess-broken" | bash "$broken/stop-guard.sh")"
check "resolve-context failure: still blocks" "$(printf '%s' "$out" | decision)" "block"
check "resolve-context failure: no world claim in reason" \
  "$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("Resolved context" not in d["reason"] and "resolves the path" in d["reason"])')" \
  "True"

[ "$fails" = 0 ] && echo "PASS test_stop_guard" || { echo "$fails failure(s)"; exit 1; }
