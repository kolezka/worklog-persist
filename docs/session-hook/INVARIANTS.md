---
block: session-hook
doc: INVARIANTS
verified_against: 3425d99
verified_on: 2026-10-16
---

# Invariants

Numbered behaviours that must hold, and the defect each one prevents. See
[`CONTRACTS.md`](CONTRACTS.md) for the interfaces these behaviours implement.

## 1. Off is OR, never AND

`scripts/persistence-state.sh::is_off()` returns true if the marker file exists
**or** `scripts/persistence-state.sh::"WORKLOG_HOOK_OFF"` is `1`; it never
requires both `[verified]`. This prevents a leftover marker file from being the
only thing keeping persistence off after an env override is removed, and
prevents an env override meant for one shell from being silently defeated by an
`on` command that only touches the file `[inferred]`.

## 2. A gate failure fails open, not closed

`scripts/session-start.sh` runs under `set -euo pipefail`, but the status check
sits inside an `if` condition
(`bash "$here/persistence-state.sh" status | grep -q '^off$'`). A nonzero exit
from that pipeline only makes the `if` false; it does not trigger `errexit`,
because commands tested by `if` are exempt from it under `set -e` `[verified]`.
So if `persistence-state.sh` ever errored before printing `on` or `off`, the
hook would fall through to emitting the reminder rather than crashing the
session start `[inferred]`. This prevents one broken shell invocation inside the
hook from blocking every new Claude Code session; the cost is that a real
failure in the state check is invisible rather than surfaced `[inferred]`.

## 3. The hook never performs an MCP call

`scripts/session-start.sh` only reads a local state file, runs the local
identity resolver and prints text; it contains no MCP tool invocation and no
network call
(`scripts/session-start.sh::"durable work-state store"` is static text, not a
tool call) `[verified]`. This keeps the hook safe to run on every session start
regardless of whether the `outline` server is even configured; the precondition
check for that lives in the skill, not here
(see [`../persistence-protocol/INVARIANTS.md`](../persistence-protocol/INVARIANTS.md))
`[verified]`.

## 4. `state_dir()` never reads a config file, only environment and `$HOME`

`scripts/persistence-state.sh::state_dir()` resolves purely from
`scripts/persistence-state.sh::"XDG_STATE_HOME"` and `$HOME`, with no plugin
config or marketplace lookup `[verified]`. This keeps the off switch usable even
when the plugin is not correctly registered with the `claude` CLI, since it does
not depend on anything `packaging` manages `[inferred]`.

## 5. The Stop guard never traps a session

`scripts/stop_guard.py::run()` returns nothing when `stop_hook_active` is set,
and records the last tool call it blocked for, so the same work is never blocked
twice (`scripts/stop_guard.py::write_marker()`) `[verified]`. When that record
cannot be written it allows the stop instead of blocking `[verified]`. Any
exception allows the stop `[verified]`. Defect prevented: a turn that can never end, or a
decline ("trivial, stopping") re-blocked on every later turn.
`tests/test_stop_guard.sh` covers both (test suite only) `[verified]`.

## 6. The off switch silences both hooks

`scripts/stop_guard.py::persistence_is_off()` asks
`scripts/persistence-state.sh` the same question `session-start.sh` does
`[verified]`. Defect prevented: `/off` quieting the reminder while the Stop hook
keeps demanding writes.

## 7. The Stop guard never blocks a session Claude Code marks unattended

`scripts/stop_guard.py::run()` checks `scripts/stop_guard.py::is_unattended()`
before it reads the transcript, and allows the stop when it is true `[verified]`.
A host that sets neither variable counts as attended, so the guard there behaves
as it did before this check existed `[verified]`.
Defect prevented: forced turns in `claude -p` and SDK runs, where nobody reads
the worklog prompt and every forced turn only adds latency and tokens.
`tests/test_stop_guard.sh::"unattended: claude -p env is silent"` covers it
(test suite only) `[verified]`.

## 8. A cooldown skip defers work, it never drops it

When the cooldown allows a stop, `scripts/stop_guard.py::run()` returns before
`scripts/stop_guard.py::write_marker()`, so the marker still points at the last
work that was shown `[verified]`. The first stop after the cooldown sees all the
work since then. Defect prevented: a burst of commits inside the cooldown that
never reaches a worklog. `tests/test_stop_guard.sh::"cooldown: new work after cooldown blocks"`
covers it (test suite only) `[verified]`.
