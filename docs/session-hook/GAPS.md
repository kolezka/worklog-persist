---
block: session-hook
doc: GAPS
verified_against: b92a027
verified_on: 2026-10-23
---

# Gaps

Debt and unenforced boundaries in this block. Fixing any of these does not
change a contract or an invariant recorded elsewhere in this block.

## SessionStart `additionalContext` delivery is a known-unreliable channel

The script's own comment names two upstream trackers:
`scripts/session-start.sh::"anthropics/claude-code #16538"` and
`scripts/session-start.sh::"VS Code #88086"`, and states the hook is
`scripts/session-start.sh::"best-effort"` while the skill is the robust driver
`[verified]`. This block cannot fix that; it can only avoid depending on the
hook for anything the skill does not also do on its own. No test in this repo
exercises the actual delivery path into a live session, only that the script
prints the right bytes to stdout `[verified]`.

## The reminder text is prefix-agnostic by omission, not by a checked rule

Nothing in `hooks/hooks.json` or `scripts/session-start.sh` enforces that the
reminder text stay silent about the MCP tool prefix. It currently is
(`scripts/session-start.sh::"durable work-state store"` names the server, not a
prefix) `[verified]`, matching the skill's own two-prefix listing
(`skills/worklog-persist/SKILL.md::"mcp__plugin_worklog-persist_outline__*"`)
`[verified]`, but
a future edit to the reminder text could hardcode `mcp__outline__*` without
failing any test owned by this block. See
[`CONTRACTS.md`](CONTRACTS.md#the-hook-names-the-server-not-a-tool-prefix).

## A renamed install can leave a stale off-marker under the old path

`scripts/persistence-state.sh::state_dir()` hardcodes the literal name
`worklog-persist`. The root `README.md::"The off-state file does not"` line
documents that a user upgrading from the older `outline-persist` plugin has
their old off-marker at a directory this resolver never reads, so persistence
silently resumes after the upgrade unless the user manually re-runs
`persistence-state.sh off` once `[verified]`. Nothing in this block detects or
warns about the stale old-path marker; it is simply orphaned.

## The `path` subcommand has no test coverage

`scripts/persistence-state.sh::"usage: persistence-state.sh {path|status|off|on}"`
lists four subcommands, but `tests/test_offswitch.sh` only calls `status`,
`off`, and `on`. `path` is untested at the pin `[verified]`.

## Unwritable state directory has no friendly error path

`scripts/persistence-state.sh` runs under `set -euo pipefail`. The `off` command
calls `mkdir -p "$(state_dir)"` before writing the marker; if the resolved
parent directory is not writable, `mkdir` fails and the script aborts on
`errexit` with `mkdir`'s own stderr message, not a `worklog-persist:`-prefixed
one `[inferred]` from the script's structure and its shell options. No test in
this repo constructs an unwritable state directory to exercise this path
`[verified]`.

## "Shipped" is a heuristic over the transcript format

`scripts/stop_guard.py::load_tool_uses()` parses Claude Code's JSONL transcript
and `scripts/stop_guard.py::WRITE_RE` recognises an Outline write by tool name
`[verified]`. A change to the transcript shape or the tool names would make the
guard silently allow every stop, or block after a write it did not recognise
`[inferred]`. Only `Bash` commands matching `scripts/stop_guard.py::SHIP_RE` trigger it, so
work shipped through an MCP tool (a GitHub MCP pull request, say) or an unlisted
deploy command never blocks, and a long session of uncommitted edits ends with no
prompt `[verified]` from `scripts/stop_guard.py::has_shipped()`. That is the
trade made in 0.3.2: an earlier edit-count and tool-count rule blocked about six
times in one long session, each costing a turn
`[historical: 2026-10-16, operator report from one long session]`.

## The attended signal rests on probed Claude Code variables

`scripts/stop_guard.py::is_unattended()` relies on `CLAUDE_CODE_SESSION_ATTENDED`
and `CLAUDE_CODE_ENTRYPOINT` from the hook's environment `[verified]`. They were
found by probing, not from a hook interface this repo can pin, and Claude Code's
own documentation for them was not checked `[verified]`. A scratch
`CLAUDE_CONFIG_DIR` with a logging Stop hook showed `ATTENDED=1`, `ENTRYPOINT=cli` for an interactive run
and `ATTENDED=0`, `ENTRYPOINT=sdk-cli` for `claude -p`, also when `-p` was
started with `cli` and `1` already in its environment. The Stop-hook stdin had no
field that tells the two apart
`[historical: 2026-10-01, scratch-config Stop-hook probe on Claude Code 2.1.286]`.
Builds before 2.1.284 were not checked. If a future build drops both variables,
the hook falls back to blocking as if a human were present `[inferred]` from
`scripts/stop_guard.py::is_unattended()`.

## The cooldown trusts clocks and record timestamps

The block side of the cooldown is the marker file's mtime, and the write side is
the transcript record's `timestamp` (`scripts/stop_guard.py::last_block_time()`,
`scripts/stop_guard.py::parse_timestamp()`) `[verified]`. A record with no
parsable `timestamp` gives no write cooldown, only the block one `[verified]`.
A time ahead of the local clock is dropped rather than trusted, so a clock moved
backwards loses the cooldown instead of muting the guard `[verified]`.

## Stop markers are never cleaned up

One file per session id under the state dir's `stop/` folder
(`scripts/stop_guard.py::state_stop_dir()`) is written and never removed
`[verified]`. If that folder cannot be written, the guard never blocks and says
nothing about why (`scripts/stop_guard.py::write_marker()`) `[verified]`.

## Native panel: what is not proven

- **No old-build or install run.** Loading this plugin, with its new `modules`
  key, in a Claude Code build without Mods has not been run, and neither has
  what `claude plugin install` or `update` does to the module.
- **Live acceptance is partial.** A read-only native probe reproduced and
  verified recovery from a large MCP result saved by the host. A later operator
  screenshot confirmed the panel showing the current project's task list.
  Explicit document loading, lifecycle actions and the pinned status line still
  need live acceptance
  `[historical: 2026-10-23, native read-only probe and operator screenshot]`.
- **Saved-result recovery has a size and format limit.** It recognizes the
  observed host notice and rejects files over 4 MiB rather than reading partial
  data (`hooks/outline-result.ts::readOutline()`) `[verified]`.
- **The tree format rests on observed responses.** `decodeTree()` follows one
  node per text block, as read from earlier sessions' saved results and one live
  call, not from a schema, since the tool declares no output schema. A server change shows as a
  decode failure, not as wrong data `[verified]`.
- **Search matches titles only.** The filter runs over the project tree's paths,
  not document bodies `[verified]`.
- **Redundant guards need isolated coverage.** The suite exercises UI event
  flows, not each internal guard separately. A passing flow test therefore does
  not prove that removing each phase or scope-token guard would fail it
  `[inferred]` from `tests/worklog-panel.test.tsx`,
  `hooks/register.tsx::runAction()` and `hooks/register.tsx::loadTask()`.
- **A held preview is fetched again.** After a same-scope refresh the preview
  is re-read from Outline, not restored from state `[verified]`.
- **Refresh after a turn runs inside `turn.complete`.** The turn's end waits for
  the Outline reads. Only a dispatched action or a non-read Outline tool call
  during the turn triggers it `[verified]`.
- **The preview text is held in session state.** A large document stays in the
  state value until the preview closes or the next refresh drops it `[verified]`.
- **The phrase is English and exact.** "show worklog panel" alone opens it `[verified]`.
