---
block: session-hook
doc: README
verified_against: 7c67f29
verified_on: 2026-10-16
owns: [hooks/, scripts/session-start.sh, scripts/persistence-state.sh, scripts/stop-guard.sh, scripts/stop_guard.py]
depends_on: [packaging, persistence-protocol]
---

# session-hook

The SessionStart hook that reminds a fresh session of the Outline durable-memory
rule, and the off switch that gates it. Read [`../CONVENTIONS.md`](../CONVENTIONS.md)
before changing anything here, and [`../README.md`](../README.md) for how this
block fits the rest of the plugin.

## What this block is

Five files. `hooks/hooks.json` wires the plugin into Claude Code's `SessionStart`
and `Stop` events `[verified]`. `scripts/session-start.sh` is the SessionStart
command; it prints one line of JSON carrying the reminder text, or nothing at all
`[verified]`. `scripts/stop-guard.sh` is the Stop command, a thin wrapper around
`scripts/stop_guard.py`: when a commit, push, PR, release or deploy happened
since the last Outline write, it blocks the stop once and asks for a checkpoint, handoff or completion.
It stays quiet in unattended sessions and for a cooldown after each block or
write `[verified]`. `scripts/persistence-state.sh` owns the single on/off marker file
that silences both hooks `[verified]`.

The hook never calls Outline and never calls an MCP tool. It only emits static
text that names the MCP server `[verified]`; resolving which tool prefix actually
answers to that name is the job of the skill in
[`persistence-protocol`](../persistence-protocol/README.md), which explicitly
warns against relying on one prefix, spelling out the plugin-scoped alternative
(`skills/worklog-persist/SKILL.md::"mcp__plugin_worklog-persist_outline__*"`)
`[verified]`.

## Boundary

This block does not own:

- the skill or the eight slash commands, including `/off`, which only wraps the
  script this block owns (`persistence-protocol`, one sentence and a link, per
  `../CONVENTIONS.md`)
- the plugin manifest, the marketplace entry, `.mcp.json`, or `install.sh`,
  including the structural check that this block's two scripts exist on disk
  (`packaging`, see [`../packaging/CONTRACTS.md`](../packaging/CONTRACTS.md))
- the test suites that exercise this block's files
  (`verification`, see [`../verification/README.md`](../verification/README.md))

## File inventory

| Path | Role |
|---|---|
| `hooks/hooks.json` | Registers `scripts/session-start.sh` against the `SessionStart` event `[verified]` |
| `scripts/session-start.sh` | Reads the off state, then emits `hookSpecificOutput.additionalContext` JSON or nothing `[verified]` |
| `scripts/persistence-state.sh` | Resolves the state directory, and implements `path`, `status`, `off`, `on` `[verified]` |
| `scripts/stop-guard.sh` | Stop hook wrapper; always exits `0` `[verified]` |
| `scripts/stop_guard.py` | Reads the transcript, decides whether to block, keeps a per-session marker `[verified]` |

## Why it depends on packaging and persistence-protocol

`${CLAUDE_PLUGIN_ROOT}` in `hooks/hooks.json::"${CLAUDE_PLUGIN_ROOT}"` is an
environment variable the plugin loader supplies, not something this block
defines `[inferred]`, and `install.sh::check_structure()` fails the whole install
if `scripts/session-start.sh` or `scripts/persistence-state.sh` is missing
`[verified]`; that ties this block to `packaging`. The `/off` command
(`commands/off.md`) and the skill both shell out to
`scripts/persistence-state.sh`, and the reminder text names the `outline` MCP
server whose prefix resolution belongs to the skill; that ties this block to
`persistence-protocol` `[verified]`.

## Flow

```mermaid
flowchart TD
    Event["Claude Code SessionStart event"] --> Hook["hooks/hooks.json"]
    Hook -->|"bash session-start.sh"| Start["scripts/session-start.sh"]
    Start -->|"status"| State["scripts/persistence-state.sh"]
    State -->|"off"| Skip["exit 0, zero bytes of output"]
    State -->|"on"| Emit["print hookSpecificOutput.additionalContext JSON"]
    Emit --> Ctx["session context"]
    EnvVar["WORKLOG_HOOK_OFF=1"] -.-> State
    OffCmd["/off (persistence-protocol)"] -.-> State
    Disable["claude plugin disable (packaging)"] -.-> Hook
    StopEvent["Claude Code Stop event"] --> Hook
    Hook -->|"bash stop-guard.sh"| Guard["scripts/stop_guard.py"]
    Guard -->|"status"| State
    Guard -->|"shipped, unpersisted, attended, past cooldown"| Block["decision: block, once"]
```

The two dotted paths cross out of this block: the env var is set by whoever runs
the session, `/off` is a persistence-protocol command, and disabling the whole
plugin is a packaging-level action that removes the hook registration entirely
rather than toggling the marker file `[verified]`.
