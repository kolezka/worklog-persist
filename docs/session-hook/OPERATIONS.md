---
block: session-hook
doc: OPERATIONS
verified_against: 3425d99
verified_on: 2026-10-16
---

# Operations

Entry points, state paths, kill switches, and stuck states for this block. See
[`CONTRACTS.md`](CONTRACTS.md) for the interfaces referenced here.

## Entry point

Claude Code's plugin loader runs `hooks/hooks.json`'s `SessionStart` command
(`bash "${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh"`) once per session start
`[verified]`. There is no manual entry point for the hook itself; running
`bash scripts/session-start.sh` directly reproduces exactly what the hook does,
which is how `tests/test_offswitch.sh` checks it `[verified]`.

## Stop guard

Claude Code runs `bash "${CLAUDE_PLUGIN_ROOT}/scripts/stop-guard.sh"` at the end of
every turn (`hooks/hooks.json::"stop-guard.sh"`) `[verified]`. To test it by
hand, pipe a Stop-hook JSON into it, as `tests/test_stop_guard.sh::input()` does.
Set `CLAUDE_CODE_SESSION_ATTENDED=1`, or unset both it and
`CLAUDE_CODE_ENTRYPOINT`. A `0`, or an `sdk-*` entrypoint with no attended flag,
makes it allow every stop (`scripts/stop_guard.py::is_unattended()`) `[verified]`. A shell
started from an interactive Claude Code session already has `1`; what a shell
started from `claude -p` gets was not checked
`[historical: 2026-10-01, Bash tool environment in an interactive Claude Code 2.1.286 session]`.

One environment variable sets how often it fires. `scripts/stop_guard.py::run()`
reads it on every stop `[verified]`:

| Variable | Default | Meaning |
|---|---|---|
| `WORKLOG_STOP_COOLDOWN_MIN` | `scripts/stop_guard.py::DEFAULT_COOLDOWN_MIN` (90) | Minutes with no block after a block or an Outline write. `0` turns it off |

Only a command that ships work can trigger a block: a commit, push, `gh pr
create`/`merge`, release, publish or deploy (`scripts/stop_guard.py::SHIP_RE`)
`[verified]`. `WORKLOG_STOP_MIN_EDITS` and `WORKLOG_STOP_MIN_TOOLS` were removed
in 0.3.2 and are ignored `[verified]`. The hook inherits the environment of the
Claude Code process, so set the variable where Claude Code is launched `[historical: 2026-10-01, scratch-config Stop-hook probe on Claude Code 2.1.286]`.
Its per-session markers live under
`scripts/stop_guard.py::state_stop_dir()`, which resolves `XDG_STATE_HOME`, else
`$HOME/.local/state`, then `worklog-persist/stop` `[verified]`.

## Checking status

```
bash scripts/persistence-state.sh status
```

Prints `on` or `off` (`scripts/persistence-state.sh::is_off()`) `[verified]`. To
find the marker file itself without guessing a path:

```
bash scripts/persistence-state.sh path
```

which prints `scripts/persistence-state.sh::state_file()`'s resolved path
`[verified]`. See [`GAPS.md`](GAPS.md) for the fact that this subcommand has no
test coverage; treat its output as informational, not as something this repo's
suite protects.

## Kill switches, and which layer each one is at

Three switches turn off persistence without uninstalling anything, and they are
not the same layer:

1. **`WORKLOG_HOOK_OFF=1`** in the environment. Checked first by
   `scripts/persistence-state.sh::is_off()`; forces `off` for that shell or
   process regardless of the marker file, and cannot be cleared by the `on`
   command `[verified]`.
2. **`bash scripts/persistence-state.sh off`** (and `on` to reverse it). Writes
   or removes the marker file at `scripts/persistence-state.sh::state_file()`.
   This is what the `/off` slash command wraps
   (`persistence-protocol`, one sentence and a link:
   [`../persistence-protocol/OPERATIONS.md`](../persistence-protocol/OPERATIONS.md)).
   Only this hook's output is affected; the skill and all eight commands still
   run `[verified]`.
3. **`./install.sh --apply --disable`**, which runs `claude plugin disable` on
   the whole plugin (`packaging`, see
   [`../packaging/OPERATIONS.md`](../packaging/OPERATIONS.md)). This removes the
   hook registration itself, not just its output, and is a different mechanism
   from switch 2 `[verified]`.

Switch 2 is the one this block owns and is the right one for "stop the
reminder, keep everything else working."

## State path resolution

Never hardcode a path. Ask `scripts/persistence-state.sh::state_dir()`: it
resolves `XDG_STATE_HOME`, falling back to `$HOME/.local/state`, then appends
the literal name `worklog-persist` `[verified]`.
`scripts/persistence-state.sh::state_file()` appends `/off` to that
`[verified]`. `tests/test_offswitch.sh` points `XDG_STATE_HOME` at a temporary
directory for its whole run so it never touches a real machine's state
`[verified]`.

## Stuck states

**Status stays `off` no matter how many times `on` is run.**
Check `echo $WORKLOG_HOOK_OFF` first. `scripts/persistence-state.sh::"WORKLOG_HOOK_OFF"`
is checked before the marker file and the `on` command cannot clear an
environment variable
(`scripts/persistence-state.sh::"off-file cleared"` warns about exactly this)
`[verified]`. Unset it in the shell or process that launches Claude Code, not in
this plugin.

**Persistence came back on after upgrading from `outline-persist`.**
The old off-marker lived under a differently-named state directory that the
current `scripts/persistence-state.sh::state_dir()` never reads
(`README.md::"The off-state file does not"`) `[verified]`. Re-run
`bash scripts/persistence-state.sh off` once after the reinstall; see
[`GAPS.md`](GAPS.md).

**`off` exits with a raw `mkdir` error instead of a `worklog-persist:` message.**
The resolved state directory's parent is not writable. Fix the permissions on
the path printed by `bash scripts/persistence-state.sh path`, or set
`XDG_STATE_HOME` to a writable directory before retrying `[inferred]` from the
script's `set -euo pipefail` and its unguarded `mkdir -p` call; see
[`GAPS.md`](GAPS.md).

**Hook seems to do nothing even with status `on`.**
That may be expected: `additionalContext` delivery has known upstream gaps in
some Claude Code builds
(`scripts/session-start.sh::"anthropics/claude-code #16538"`) `[verified]`. Do
not chase this further inside this block; confirm the skill still injects the
rule on its own, since it is the primary driver
(`scripts/session-start.sh::"best-effort"`) `[verified]`.

**The Stop guard does not fire after work you expected it to catch.**
Usually expected. With no commit, push, PR, release or deploy since the last
write, inside the cooldown, or in an unattended session it allows the stop on
purpose
(`scripts/stop_guard.py::run()`) `[verified]`. It also stays silent when it
cannot write its marker under `scripts/stop_guard.py::state_stop_dir()`
`[verified]`, so check that folder is writable. Check the variable in the
table above, then pipe the session's Stop-hook JSON into
`scripts/stop-guard.sh` by hand with the same environment. Do not delete the
session marker to force a block; set `WORKLOG_STOP_COOLDOWN_MIN=0` for that run
instead.
