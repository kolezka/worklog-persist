---
block: session-hook
doc: INVARIANTS
verified_against: b92a027
verified_on: 2026-10-23
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

## 9. The panel never writes to Outline and never bootstraps

The panel only reads (see [CONTRACTS](CONTRACTS.md#outline-is-read-with-three-tools-never-written)).
An ignored repo, an unresolved world, a broken config or a missing folder is
reported and stops the read; nothing is created
(`hooks/register.tsx::refresh()`) `[verified]`. Writes happen only inside the
slash commands it dispatches. Defect prevented: a viewer that creates folders a
person never asked for.

## 10. Only the current project is shown

`hooks/worklog-panel.ts::resolveScope()` walks the resolver's `kb_path` title by
title through the collection tree; two siblings with the same title are an
error, not a guess. Preview and task reads go through
`hooks/register.tsx::fetchInScope()`, which refuses an id outside that subtree
and an answer whose id or parent differs from the request `[verified]`.
Defect prevented: a same-named project in another world leaking into the pane.
`tests/worklog-panel.test.tsx::"a same-named project in another world never appears"`
and `tests/worklog-panel.test.tsx::"a preview of a document outside the project is refused"`
cover it (test suite only).

## 11. A failed read is a failure, never an empty project

Every decoder throws on an unknown shape, and `refresh()` shows the error with a
Retry button; "No task records" is drawn only for a decoded, empty `Tasks`
folder `[verified]`. Defect prevented: a gateway error page read as "nothing
recorded yet".

## 12. Nothing of an old snapshot is shown or used before the scope is confirmed

A refresh empties the project identity, persistence indicator, documents, active
task, task detail, preview and any action still being edited before it reads anything; while it runs no
action, task, preview or Load can start (`hooks/register.tsx::refresh()`,
`hooks/register.tsx::fetchInScope()`) `[verified]`. A stop (ignored,
unresolved, broken config, missing folder, failure) keeps them empty. The active
task and the open preview are held aside and come back only when a later refresh
resolves the same `kb_path` and both ids are still in its tree. Defect
prevented: an ignored or changed project still showing, or loading, the previous
project's documents.
`tests/worklog-panel.test.tsx::"a refresh hides the old preview and Load until the scope is confirmed"`,
`tests/worklog-panel.test.tsx::"an ignored scope shows none of the old project"` and
`tests/worklog-panel.test.tsx::"the selection survives a refresh of the same scope, not a different one"`
cover it (test suite only). The old project label and persistence indicator also
stay hidden during resolution or a resolver failure, covered by
`tests/worklog-panel.test.tsx::"a refresh hides the previous project label and persistence indicator"`
and `tests/worklog-panel.test.tsx::"a malformed resolver response never leaves the last project in the header"`
`[verified]`.

An unplaced open clears the snapshot too: the engine may render the pane later,
so it must not retain a prior project's body or Load action
(`hooks/register.tsx::open()`) `[verified]`.
`tests/worklog-panel.test.tsx::"an unplaced reopen clears the old snapshot before a surface later attaches"`
covers the delayed attachment path (test suite only).

## 12a. An older answer never replaces a newer one

Each refresh, task read and preview carries a token; a response whose token is
no longer current is dropped (`hooks/register.tsx::showPreview()`,
`hooks/register.tsx::loadTask()`), and so is a task or preview read that lands
after another refresh started `[verified]`. Load reads the preview that is
current when pressed. Defect prevented: a slow preview of one document being
loaded after the person picked another.
`tests/worklog-panel.test.tsx::"a stale preview response cannot replace a newer selection"`,
`tests/worklog-panel.test.tsx::"a task read that lands after a scope change is dropped"` and
`tests/worklog-panel.test.tsx::"an older overlapping refresh cannot replace a newer one"`
cover it (test suite only).

## 13. No active task is guessed; preview never retargets it

The active task is set only by pressing a task; nothing picks one from dates or
order. Previewing a checkpoint or any document leaves it unchanged `[verified]`.
Defect prevented: a checkpoint written to the wrong record.

## 14. Preview adds nothing to the conversation

Only the Load button calls `$.session.append` `[verified]`.
`tests/worklog-panel.test.tsx::"preview shows the body and adds nothing to the conversation"`
covers it (test suite only). Defect prevented: browsing history filling the
model's context.

## 15. A dispatched command is not a write

An action moves through queued, dispatched, then "turn ended" after the next
main-loop `turn.complete`, which refreshes the snapshot; no state says saved.
While one is queued or dispatched no other action can be started, and an
action picked under one refresh cannot run under another
(`hooks/register.tsx::pickAction()`, `hooks/register.tsx::runAction()`) `[verified]`.
`setup` and `off` stay offered in an ignored or unresolved repo; a task action
there asks for a task, since none is active. Defect prevented: reporting
success from a command that only queued, and double dispatch.

## 16. Another directory's snapshot is never drawn

`session.start` (also run on a reload) empties the state when the stored
`cwd` differs from `$.session.cwd()`, and `session.end` with reason `clear`
empties it always `[verified]`. Defect prevented: a moved or cleared session
showing the previous project.

## 17. A saved-result notice cannot authorize arbitrary file reads

`hooks/outline-result.ts::readOutline()` confines recovery to the current
session's tool-results directory and the exact server/tool filename prefix,
checks the resolved path, and rejects oversized or malformed files
`[verified]`. Defect prevented: a forged
MCP notice reading another session's output or a private file. Recovered blocks
still pass the existing Outline shape and project-scope checks; a file pointer
is not evidence that the document belongs to this project
`[verified]`.
