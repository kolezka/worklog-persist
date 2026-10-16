---
block: persistence-protocol
doc: DECISIONS
verified_against: 7c67f29
verified_on: 2026-10-16
---

# Decisions

Why this block is shaped this way, and what it deliberately gave up.

---

## The skill holds the contract; commands are one-line pointers

`skills/worklog-persist/SKILL.md::"This skill is the operational contract"`
[verified], and every command body's first line is
"Run the worklog-persist skill's **\<verb\>** step"
(`commands/handoff.md::"Run the worklog-persist skill's"`) [verified] rather
than a restatement of the lifecycle rules. The alternative that lost: writing
the full read/redact/idempotency/labeling logic into each of the eight command
files (or into the SessionStart hook, which instead only reminds the agent of
the rule per [`../session-hook/README.md`](../session-hook/README.md)). That
would mean eight, or nine, near-duplicate copies of the same rules drifting
apart the first time one of them needed a fix
[inferred: the one-file-plus-pointers shape only makes sense as a defense
against that drift; no comment in the source names the rejected alternative
directly].

## A stable key, never a timestamp

`skills/worklog-persist/SKILL.md::"Never use a timestamp as document identity."`
[verified]. The alternative that lost: naming each checkpoint's record by when
it was written (e.g. one document per session or per day). That would break the
"same document, updated" promise in
`commands/checkpoint.md::"idempotency key = project + task slug"` [verified]:
every checkpoint would instead create a new document, and `/load` would have no
single place to read from. The key actually chosen, `project` + `task_slug`
(`skills/worklog-persist/SKILL.md::"The record identity is"` [verified]),
survives renames of nothing but the task itself.

## Current state in the record, history in child docs

Up to 0.3.1 every checkpoint added a section to the one record, so a long task's
record grew to tens of thousands of characters, and because `update_document`
returns the whole body, each of 25 writes in one session put the full record back
into context [historical: 2026-10-16, operator report from one long session].
From 0.3.2 the record is current state only, patched in place, and history goes
to dated child docs (`skills/worklog-persist/SKILL.md::"Checkpoint history: child documents"`)
[verified]. This does not reopen the timestamp decision above: the record is
still found by slug, and a child is only ever reached through its record
[inferred: children have no identity of their own outside the parent]. The
alternatives that lost: appending with `editMode: "append"` (the response is
still the whole body), and one history doc per task (it grows the same way).
The cost: `/load` sees only the latest 5 checkpoints by link, and reading older
history takes extra fetches [inferred from the Checkpoints section rule].

## Redaction is a filter, not a substitute for the rule

`scripts/redact.py::"defence-in-depth filter"` [verified] and
`scripts/redact.py::"do not put secrets into the record in the first place"`
[verified] both appear in the module's own docstring. The alternative that
lost: relying only on the skill's prose instruction
(`skills/worklog-persist/SKILL.md::"Never persist secrets"` [verified]) and
trusting the agent never to compose a secret into a body in the first place.
The recorded reasoning keeps both: the prose rule stays the primary control,
and `scripts/redact.py::redact()` is a mechanical backstop for the cases where the
primary rule is followed imperfectly, at the cost of being only as good as its
fixed pattern list (see [`GAPS.md`](GAPS.md)).

## World is resolved, never named

`scripts/resolve_context.py::"No world name is"` [verified] and
`skills/worklog-persist/SKILL.md::"is never hardcoded"` [verified] say the same
thing from two files. Two operators declare different worlds, so any world name
written into this plugin would be right for at most one of them [inferred]. The
alternative that lost: hardcoding the world this plugin happened to be built
against, which is exactly the shape `tests/test_context.sh::"WORKLOG_WORLD honored"`
[verified] exists to keep out, by proving the value actually comes from the
environment.

## Its own config, not a shared manifest

[historical: 2026-09-28, this change] Up to 0.2 the resolver read a YAML
manifest owned by a separate KB tool, plus that tool's world env var, and
offered a local read-only mirror written by the same tool. 0.3 cuts all of it.
The plugin now reads only its own YAML file
(`scripts/resolve_context.py::config_path()`) and `$WORKLOG_WORLD` [verified].
Why: a shared file couples two release cycles. The alternatives that lost:
reading both files with the old one as a fallback (two sources of truth for the
same world), and keeping the old env var as an alias (a stale shell export
would keep routing records with no visible cause). The cost: until a repo is
onboarded it resolves to `UNRESOLVED` with `config_error` set.
`tests/test_context.sh::"old coupling ignored"` [verified] keeps the old names
from quietly coming back.

## YAML, not TOML

[historical: 2026-09-28] An interim 0.3 draft used TOML through the standard
library `tomllib`, which removed the PyYAML dependency. The operator chose YAML:
the schema is the one operators already have, so upgrading is a copy, not a
rewrite, and the writer can dump YAML with the same library it reads it with
(the standard library cannot write TOML) [inferred]. The cost is PyYAML as a
runtime dependency again; its absence is reported, never a crash
(`scripts/resolve_context.py::"PyYAML is not installed"`) [verified].

## Onboarding through a writer script, worlds read from Outline

The hook cannot prompt, so it injects an instruction to run onboarding
(`scripts/session-start.sh::"run the onboarding flow"`) [verified]. The agent
asks, and `scripts/config-add.sh` writes. Why a script: the rules that keep the
file safe (no duplicates, no silent move to another world, never rewrite a
file it cannot parse, atomic replace) are code that `tests/test_config_add.sh`
can check, where an agent editing YAML by hand could break any of them
[inferred]. Why worlds come from Outline: the top-level documents under
`root_collection` are the worlds that actually exist, so a list in the config
or in the plugin would drift from them [inferred]. The alternatives that lost:
letting the agent edit the YAML, and offering only `candidate_worlds` from the
config, which is empty for a new operator.

## No offline mirror

The mirror was a snapshot written by another tool, so `/load` could report
stale state as current. With the cut above there is no writer for it in this
plugin. `/load` now says persistence is unavailable and stops
(`commands/load.md::"say persistence is unavailable and stop"`) [verified].

## Two MCP tool prefixes, neither one pinned

[historical: 2026-09-24, commit `8b3075f`] The skill used to hardcode
`mcp__outline__*`. On a machine where only this plugin's own `.mcp.json`
defines the `outline` server, Claude Code exposes the tools as
`mcp__plugin_worklog-persist_outline__*` instead, and the old skill text found
nothing under the name it searched for, so the agent reported Outline as
unavailable when it was actually just unnamed correctly. The fix, still current
at this pin, names both prefixes and finds the live one by keyword
(`skills/worklog-persist/SKILL.md::"Find them with ToolSearch"` [verified]),
locked in by
`tests/test_structure.sh::"skill handles both MCP tool prefixes"` [verified].
The alternative that lost: keeping a single hardcoded prefix and requiring
every installation to also register a user- or project-scope `outline` server
just so the old string would resolve.

## Default collection names stay neutral placeholders; `root_collection` stays optional

[historical: 2026-10-16, this change] `DEFAULT_OUTLINE["root_collection"]` used
to name one operator's real Outline collection, so a public copy of this plugin
leaked that operator's KB name to anyone who read the source, and every repo
that routed through the default (rather than an explicit `outline:` block)
silently depended on it. The alternative considered: make a missing
`root_collection` a hard failure (`kb_path` becomes `None` with a loud message
naming `config_path`), the same way an `UNRESOLVED` world already does. That
alternative lost: `scripts/session-start.sh` treats a falsy `kb_path` as proof
the *world* is unresolved and writes "World for project X is unresolved" into
the reminder; a repo whose world resolves normally but whose `root_collection`
is simply unset would get that same, now-wrong, message. Fixing that needs a
third case in a different block's contract
([`../session-hook/CONTRACTS.md`](../session-hook/CONTRACTS.md)), out of scope
for a privacy cleanup. The fix taken instead: `DEFAULT_OUTLINE` keeps its
three-key fallback contract exactly as before; only the values changed to
neutral placeholders (`"Worklog"` for `root_collection`) that name nothing
about any real operator. An operator who was relying on the old default must
now set `outline.root_collection` explicitly; see
[`README.md`](../../README.md#install).

## Path root kept, overlay discovery dropped

[historical: 2026-09-28, merge of the Stop guard branch] Master added two
inference tiers: a scan of every `worlds*.yaml` next to the active manifest, and
path root. This plugin keeps path root, computed over its one config
(`scripts/resolve_context.py::world_repo_roots()`), because it places a repo by
where it lives, with no second file [verified]. It drops the overlay scan and
the output key naming the matched file: that is the old shared-manifest layout, and
reading neighbour files would bring back the coupling this plugin cut [inferred].
The resulting order is config, `$WORKLOG_WORLD`, path root, `UNRESOLVED`.
`$WORKLOG_WORLD` sits above path root, as the old env var sat above it on master
[verified]. `tests/test_context.sh::"old coupling ignored"` includes an overlay
file, so the scan cannot quietly return [verified].
