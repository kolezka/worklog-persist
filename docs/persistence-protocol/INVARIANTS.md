---
block: persistence-protocol
doc: INVARIANTS
verified_against: fcd9e31
verified_on: 2026-10-23
---

# Invariants

Numbered behaviours the protocol text requires, and what breaks if a session
does not follow them. None of these are enforced at agent run time; see
[`GAPS.md`](GAPS.md) for what that means in practice.

---

### 1. Never write a secret into a persisted record

`skills/worklog-persist/SKILL.md::"Never persist secrets"` [verified]. Every
write-capable command routes the body through `scripts/redact.py::redact()`
first, e.g. `commands/start.md::"Pipe the body through"` [verified]. Defect
prevented: a durable, shared wiki record permanently holding a live API key,
password or PII, which is worse than a leak in a transcript because Outline is
built to be found and reused later [inferred: the skill's own framing of
Outline as durable makes an unredacted secret durable too].

### 2. Confirm availability before any read or write

`skills/worklog-persist/SKILL.md::"confirm the server is connected"` [verified].
Defect prevented: silently skipping the read/write step and letting the agent
proceed on stale or absent context without saying so, or worse, treating a
failed remote call as if it had succeeded.

### 3. Never claim a write succeeded without a confirming response

`commands/start.md::"Do not claim success unless the Outline response confirms the write."`
[verified], repeated for handoff as
`commands/handoff.md::"Report the write only after the Outline response confirms it."`
[verified]. Defect prevented: the next session trusting a record that was never
actually written, because the current session reported success from having
sent the call, not from Outline's response.

### 4. One record per (project, task slug), never a second one

`skills/worklog-persist/SKILL.md::"The record identity is"` [verified];
`commands/checkpoint.md::"idempotency key = project + task slug"` [verified].
Defect prevented: two documents for the same task drifting apart, so `/load` in
a later session reads a stale or partial one depending on which it happens to
find.

### 5. A task slug is validated kebab-case or the script fails loud

`scripts/resolve_context.py::SLUG_RE` [verified]; on mismatch the script exits
`2` rather than returning a malformed slug
(`scripts/resolve_context.py::"invalid task slug"`) [verified]. Defect
prevented: a slug like `My Task` or `Fix_Bug` silently becoming part of the
idempotency key in invariant 4, so two spellings of the same task each get
their own document.

### 6. World comes from the plugin config, `$WORKLOG_WORLD` or a sentinel, never hardcoded

`scripts/resolve_context.py::"WORKLOG_WORLD"` [verified]. Path root reads the
same single config, never another file next to it
(`scripts/resolve_context.py::world_repo_roots()`) [verified]. No other env var
or file feeds it. Defect prevented: the plugin's identity-resolution code naming
one operator's world, or picking one up from another tool's settings, which
would make a session write to the wrong place with no visible cause.
`tests/test_context.sh::"WORKLOG_WORLD honored"` exercises the override path and
`tests/test_context.sh::"old coupling ignored"` proves the pre-0.3 names, and an
overlay manifest next to the old default path, have no effect (test suite only)
[verified].

### 7. Redaction does not rewrite text that was never secret-shaped

`tests/test_redact.py::test_preserves_ordinary_text()` [verified]. Defect
prevented: `redact()` over-matching and corrupting an ordinary record body
(branch names, file paths, prose), which would make the persisted record less
trustworthy than the one it replaced.

### 8. Redaction is idempotent

`tests/test_redact.py::test_idempotent()` [verified]. Defect prevented: running
the filter twice (for instance once in `/checkpoint` and again if a caller
pipes an already-redacted body through it a second time) producing a
double-redacted, harder-to-read artifact such as nested `<REDACTED:` markers.

### 9. Completion is not claimed from file changes alone

`commands/complete.md::"Do not mark complete merely because files changed."`
[verified]. Defect prevented: a task marked `complete` in Outline while its
acceptance criteria were never actually verified, which a later session would
trust at face value per invariant 3's own logic.

### 10. A bad config never crashes the resolver

`scripts/resolve_context.py::load_config()` returns an error string instead of
raising for a missing, unparseable or wrongly shaped file [verified]. Defect
prevented: one broken config file making `resolve-context.sh` exit non-zero,
which would break every command and leave the SessionStart hook without an
identity. `tests/test_context.sh::"malformed config"` and
`tests/test_context.sh::"unparseable config"` cover it (test suite only)
[verified].

### 11. An ignored repo gets no Outline folder, even with `$WORKLOG_WORLD` set

`scripts/resolve_context.py::"An ignored repo has no Outline folder"` [verified].
Defect prevented: an env var set for one repo routing records for a repo the
operator excluded on purpose. `tests/test_context.sh::"ignored beats WORKLOG_WORLD"`
covers it (test suite only) [verified].

### 12. The config writer never clobbers a file it cannot read

`scripts/config_add.py::load()` raises before any write when the existing file
does not parse or fails the shape check, and `main()` returns `1` without
calling `write()` [verified]. Defect prevented: onboarding one repo silently
replacing an operator's hand-kept config with a one-entry file.
`tests/test_config_add.sh::"unparseable file refused"` and
`tests/test_config_add.sh::"malformed file refused"` check the file stays
byte-identical (test suite only) [verified].

### 13. The config writer is idempotent and never moves a repo

The same entry twice leaves the file untouched; a repo declared under another
world is refused (`scripts/config_add.py::add_project()`) [verified]. Stored
paths are compared as their main checkout, so this holds for entries an older
version stored under a worktree path or in another case. Declared again
unchanged, such an entry is rewritten once to the canonical path so it routes,
or dropped when an entry with that path already exists, so the same repo never
appears twice (`scripts/config_add.py::add_ignore()` does the same for
`ignore`) [verified]. Defect
prevented: duplicate entries where the first match wins, or records for one
project silently starting to land in another world's folder.
`tests/test_config_add.sh::"idempotent re-add: byte-identical"`,
`tests/test_config_add.sh::"conflict: file untouched"`,
`tests/test_config_add.sh::"stale worktree entry: other world refused"`,
`tests/test_config_add.sh::"stale worktree entry: same entry rewritten"`,
`tests/test_config_add.sh::"stale beside canonical project: one entry left"`,
`tests/test_config_add.sh::"stale beside canonical ignore: one entry left"` and
`tests/test_config_add.sh::"stale case entry: other world refused"` cover it
(test suite only; the case test runs only on a case-insensitive disk)
[verified].

### 14. World names come from Outline or the user, never from the plugin

Onboarding lists the top-level documents under `root_collection` each time and
never caches them
(`skills/worklog-persist/SKILL.md::"remember or cache world names"`)
[verified]. Defect prevented: a stale or foreign list steering a repo into a
world that does not exist for this operator. Convention only; no test drives
the flow [verified].

### 15. Path root never guesses between worlds

`scripts/resolve_context.py::path_root_world()` returns nothing when two
different worlds tie for the deepest root [verified]. Defect prevented: a repo
in a shared parent dir landing in whichever world happened to be listed first.
`tests/test_context.sh::"equal-depth tie is ambiguous"` covers it (test suite
only) [verified].

### 16. A missing Outline target is created, never a silent skip

`skills/worklog-persist/SKILL.md::"Never skip a write because a target is missing"`
[verified]. Bootstrap creates a missing `root_collection` with `create_collection`,
then any missing world folder, project folder, `INDEX` or `Tasks` parent, and
reports each one it created [verified]. `/checkpoint`, `/handoff` and
`/complete` run `/start` first when the record or its folder is missing
(`commands/checkpoint.md::"never skip the write"`) [verified]. A near match
(other case or spacing) is asked about, not duplicated [verified]. Load stays
read-only and names what is missing [verified]. Defect prevented: a fresh
operator, or a config whose `root_collection` names nothing yet, losing every
record while the session carries on as if persistence worked.
`tests/test_structure.sh::"missing Outline targets are created, not skipped"`
checks the text is present (test suite only); no test drives the Outline calls
[verified].
