---
block: persistence-protocol
doc: OPERATIONS
verified_against: 2d0b8af
verified_on: 2026-10-18
---

# Operations

Entry points, where identity comes from, the kill switches this block exposes
versus the one it only calls, and known stuck states.

---

## Entry points

Eight slash commands, each a thin pointer into
`skills/worklog-persist/SKILL.md::"This skill is the operational contract"`
[verified]:

| Command | Effect | Writes? |
|---|---|---|
| `/load` | `commands/load.md::"Load current work-state from Outline before starting substantive work."` | No, `commands/load.md::"Read-only. Do not write."` [verified] |
| `/start` | `commands/start.md::"Create or update the Outline task record at the start of a work item."` | Yes |
| `/checkpoint` | `commands/checkpoint.md::"Update the same Outline task record after a verified milestone."` | Yes, update only |
| `/handoff` | `commands/handoff.md::"Write a compact handoff state when the session ends, is blocked, or is transferred."` | Yes, update only |
| `/complete` | `commands/complete.md::"Record the real completion result of a work item in Outline."` | Yes, update only |
| `/dry-run` | `commands/dry-run.md::"Show the intended Outline read or write without changing anything."` | No, `commands/dry-run.md::"Output the plan only. Make no mutation to Outline."` [verified] |
| `/off` | `commands/off.md::"Disable automatic Outline persistence without removing the plugin."` | No Outline write; toggles a local switch, see below |
| `/setup` | `commands/setup.md::"Route this repo to an Outline world, or mark it as not persisted."` | Writes the config through `config-add.sh`; bootstraps Outline folders when connected |

All descriptions above are the command's own front-matter `description:` field,
read verbatim [verified].

## Identity: what `resolve-context.sh` resolves and what it does not

Run as `scripts/resolve-context.sh [task-slug]`
(`scripts/resolve_context.py::"Usage: resolve_context.py [task-slug]"`)
[verified]. It resolves `repo`, `project`, `branch` and `worktree` from git, then
looks the main checkout up in the plugin config, then falls back to
`$WORKLOG_WORLD`, then to path root (the config world whose repos it sits
under), then to the `UNRESOLVED` sentinel. Full field-by-field
contract: [`CONTRACTS.md`](CONTRACTS.md). It writes nothing to disk; it only
prints JSON to stdout. There is no cache and no local record of a previously
resolved identity, so every command re-resolves it fresh [verified].

## Where the config lives

Ask the resolver, never restate the path: `scripts/resolve_context.py::config_path()`
reads `WORKLOG_CONFIG`, else falls back to a file under `$HOME/.config`
[verified]. The JSON field `config` names the file actually read, and
`config_error` says why none was [verified]. To test a config without touching
the real one, point `WORKLOG_CONFIG` at a scratch file for one command.

## Kill switches

This block owns one entry point into a kill switch it does not implement:
`/off` calls `commands/off.md::"bash ${CLAUDE_PLUGIN_ROOT}/scripts/persistence-state.sh off"`
[verified] (and `... on`, `... status`). The switch itself, the state file it
writes and where that file resolves belong to
[`session-hook`](../session-hook/README.md); see
[`session-hook/OPERATIONS.md`](../session-hook/OPERATIONS.md) for the actual
path and precedence, per the "ask the component where it writes" rule in
[`../CONVENTIONS.md`](../CONVENTIONS.md). The same command also names a second,
independent override: `commands/off.md::"WORKLOG_HOOK_OFF=1"` [verified] forces
off from the environment without touching that state file.

`/dry-run` is the closest thing to a kill switch inside this block itself: it
runs identity resolution and shows the redacted body a real write would send,
but calls no write tool
(`commands/dry-run.md::"Call NO write tool."`) [verified].

## Stuck states

- **World stuck at `UNRESOLVED`.** Check `config_error` in the resolver output
  first. `config not found` means no config file exists at the resolved path;
  `config unreadable` or `config malformed` means the file is there but was
  rejected (`scripts/resolve_context.py::load_config()`) [verified]. While the
  world is `UNRESOLVED`, `kb_path` is `None`, so no path is built from the
  sentinel [verified]. Recovery: declare the repo in the config, or set
  `WORKLOG_WORLD`, or run `/setup`
  (`commands/setup.md::"Onboarding"`) [verified].
- **`config-add.sh` refuses.** Exit `1` means nothing was written. The message
  names the cause: an existing different declaration, an ignore conflict, a file
  it cannot parse, or no PyYAML (`scripts/config_add.py::Refused`) [verified].
  Recovery: the operator fixes the file or picks another answer; never edit
  around the refusal by hand.
- **Invalid task slug.** The script exits `2` rather than guessing a
  normalization
  (`scripts/resolve_context.py::"invalid task slug"`) [verified]. Recovery:
  supply a lowercase kebab-case slug; `/load` also lets the session
  `commands/load.md::"ask the user for the slug if unclear"` [verified].
- **Outline unavailable.** No queue, no retry, no local read or write path is
  defined here beyond the skill's explicit escape hatch: state it once and keep working
  without Outline
  (`skills/worklog-persist/SKILL.md::"state once that persistence is"`)
  [verified]. Recovery: nothing to do locally; the next successful availability
  check on a later command picks the work back up.
- **A duplicate record already exists** (created before a slug was made
  consistent, or by a session that skipped the `list_documents` match step).
  Nothing here detects an existing duplicate beyond matching the current slug
  exactly; recovery is a manual merge in Outline. See
  [`GAPS.md`](GAPS.md) for why no test catches this case.
