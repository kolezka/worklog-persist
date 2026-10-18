---
name: worklog-persist
description: Use whenever you start, checkpoint, hand off, or finish non-trivial work, or need prior context on a task/feature/bug/decision. Durable work-state persistence backed by the Outline MCP server — read current state before acting, record task start, checkpoint at verified milestones, write handoff and completion.
version: 0.3.0
---

# worklog-persist: durable work-state persistence

Outline is durable; conversation context is volatile. The state of active
engineering work lives in Outline so it survives across sessions: what task is in
progress, what was verified, what changed, which decisions were made, what is
blocked, and what the next action is.

This skill is the operational contract. The eight slash commands
(`/load`, `/start`, `/checkpoint`, `/handoff`, `/complete`, `/dry-run`, `/off`,
`/setup`) are thin entry points that run the relevant part of this contract.

The Outline tools are `list_collections`, `create_collection`, `list_documents`,
`fetch`, `create_document`, `update_document` and `move_document`. Their prefix depends on
where the `outline` server is configured:

- `mcp__outline__*` when the user also configures `outline` at user, project or
  local scope. Claude Code then connects once, using that definition.
- `mcp__plugin_worklog-persist_outline__*` when only this plugin's `.mcp.json`
  defines it.

The tools may be deferred. Find them with ToolSearch (query `outline
list_collections`), then load the schemas of the prefix that exists. Never assume
one prefix.

Helper scripts live under `${CLAUDE_PLUGIN_ROOT}/scripts/`:
`resolve-context.sh` (identity), `config-add.sh` (the only config writer),
`redact.py` (secret redaction), `persistence-state.sh` (the off switch).

## Precondition: is Outline available?

Before any read or write, confirm the server is connected: attempt
`list_collections`. If it errors as unavailable, **state once that persistence is
unavailable and continue the task without Outline** — never block work, never
substitute a local success claim for a failed remote write. A local pending
record is allowed only if this repository already has a supported local fallback;
mark it explicitly as `pending, unsynchronized`.

## Never persist secrets

Never write secrets, tokens, API keys, passwords, private keys, cookies, customer
PII, NIPs or account numbers to Outline. Pipe every candidate record body through
`python3 ${CLAUDE_PLUGIN_ROOT}/scripts/redact.py` before `create_document` /
`update_document`; it replaces secret-shaped values with `<REDACTED:kind>`. If the
user pastes a secret, redact it and warn inline. Do not log authorization headers
or raw MCP payloads.

## Identity and world resolution

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-context.sh [task-slug]`. It prints
JSON. Use its paths as given; never rebuild them by hand.

| Field | Meaning |
|---|---|
| `world`, `project` | From the plugin config when the repo is declared there, else inferred |
| `world_source` | `config`, `env` (`$WORKLOG_WORLD`), `path-root` or `fallback` |
| `kb_path` | Project folder in Outline (`kb_folder` override, else `<root>/<World>/<project>`) |
| `tasks_path`, `record_path` | `<kb_path>/Tasks` and `<kb_path>/Tasks/<slug>` |
| `root_collection`, `global_collection`, `archive_collection` | From the config `outline:` block |
| `repo_root`, `worktree`, `branch` | `repo_root` is the main checkout, also from a linked worktree |
| `ignored` | The config lists this repo, or a parent dir, under `ignore` |
| `candidate_worlds` | The world names declared in the config |
| `config`, `config_error` | Which config was read, or why none was |
| `config_path` | Where the config is looked for, also when it does not exist |

The config is this plugin's own YAML file: `$WORKLOG_CONFIG`, else
`~/.config/worklog-persist/config.yaml`. Reading it needs PyYAML. Pointing
`WORKLOG_CONFIG` at another file lets the same repo resolve differently per
context. That is intended. Never edit the file by hand: add entries only with
`config-add.sh` (see Onboarding).

- **World** is never hardcoded. Precedence: (1) the repo is declared in the
  config (`world_source` `config`); (2) `$WORKLOG_WORLD` (`env`); (3) path root:
  the config world whose declared repos' common ancestor is the deepest
  ancestor-or-equal of this repo (`path-root`; a tie between two different worlds
  at that depth stays unresolved, never guessed); (4) `UNRESOLVED`. An ignored
  repo gets no world from tiers 2 or 3. On `UNRESOLVED`, run Onboarding (below)
  before any other work. Do not write anything to Outline until the world is
  known. A `path-root` world is resolved, not a guess to confirm; if the operator
  says it is wrong, run `/setup` to declare the repo.
- **Project** is the config `name` when declared (it can differ from the repo
  name), else the basename of `git remote get-url origin`, else the main checkout
  directory name. A worktree directory name is never the project. When the current
  directory is not a git repo at all, project is `workspace`, never the directory's
  basename.
- **Ignored repo**: the operator decided it has no Outline folder. Do not bootstrap
  one. Ask before writing anything for it.
- **Task slug**: lowercase kebab-case, shared across `Specs`/`Plans`/`Tasks`.
  Ticket-backed work prefixes the ticket ID: `AD-163-uat-checklist`.

## Structure and routing

Names in angle brackets come from the resolver.

```
<root_collection>/                 active KB (default "Worklog"; set outline.root_collection in config)
  <World>/                         INDEX only
    <project>/                     = kb_path
      INDEX                        project hub
      Specs/  Plans/  Tasks/       parents with child lists
      Tasks/<slug>                 = record_path, one per work item, current state only
        <YYYY-MM-DD> <short title> checkpoint history, one child doc per checkpoint
      Tasks/BACKLOG                trivial items, until they grow up
      Packages/<pkg>/              monorepo sub-packages only
    status-reports/  analizy/      per-world, not project work
<global_collection>                Claude's Notebook: SOUL, CONVENTIONS, LESSONS, STACK-NOTES
<archive_collection>               retired content, Archive/Security
```

- Work records go to `record_path`. Prefer updating an existing doc over a new one.
- Cross-project lessons and conventions go to `global_collection`. If it is
  missing, create it once as in Bootstrap step 2; never create a second global KB.
- Never delete. To retire a doc, move it to `archive_collection`.
- Outline addresses are chains of **titles**. Renaming a folder or doc breaks every
  `[[link]]` to it. Rename only on request, and across Specs/Plans/Tasks together.
- Document bodies must not begin with an H1. The title is a separate field.

## Bootstrap (lazy, idempotent)

Run before the first write in a session, never before a read-only load.

**Never skip a write because a target is missing.** A missing collection, world
folder, project folder, `Tasks` parent or record is created here, then the write
goes ahead. Stopping is right only for an `ignored` repo, an `UNRESOLVED` world,
a missing root collection that only the default names (step 2) or Outline being
unavailable, and each of those is reported, never silent.

1. Resolve identity. On `UNRESOLVED` run Onboarding; on an `ignored` repo stop.
2. Find the collection named `root_collection` (the first segment of `kb_path`) in
   the `list_collections` result. If it is missing, create it with
   `create_collection` and say so in one line. If only a near match exists (other
   case or spacing), do not create a second one: ask whether the config or the
   collection name is wrong. If `root_collection_source` is `default`, never create
   it: the config names no collection, so a new one would split the KB on a machine
   whose config is incomplete. Ask which existing collection to use and have the
   operator set `outline.root_collection` in the file at `config_path`.
3. Resolve each remaining segment of `kb_path` with `list_documents`. Create only
   what is missing, and check each child before you create it. This repairs a
   partial folder and never duplicates.
4. Seeding shape depends on depth: a **world** folder gets `INDEX` only; a
   **project** folder gets `INDEX`, `Specs`, `Plans`, `Tasks`. Never seed
   `Specs`/`Plans`/`Tasks` at world level. Running bootstrap twice creates nothing
   new.
5. A folder that has no `INDEX` is a hub gap. Create the `INDEX`, do not skip it
   silently.
6. Report what bootstrap created, one line per collection or folder. A failed
   create stops the write and is reported with the Outline error.

## Onboarding (unresolved repo)

Run this when the resolver reports `world` = `UNRESOLVED` and `ignored` = false,
and `config_error` is empty or starts with `config not found`. The SessionStart
hook asks for it, and `/setup` runs it. If `config_error` says the file is
unreadable or malformed, do not onboard: report the error and `config_path`, and
ask the operator to fix the file.

1. **Discover worlds.** Run the availability check. If Outline is connected,
   `list_documents` directly under `root_collection` (top level only). Each
   top-level document title there is a world. Read them live every time: never
   hardcode, remember or cache world names.
2. **Ask one question.** Offer: each discovered world, "New world" (the user types
   the name), and "Do not persist this repo". In the same question, confirm the
   project name; the default is the resolver's `project`.
3. **Record the answer** with the script, never by editing the YAML:
   - world picked or typed:
     `bash ${CLAUDE_PLUGIN_ROOT}/scripts/config-add.sh project --world <World> --name <project> --repo <repo_root>`
   - do not persist:
     `bash ${CLAUDE_PLUGIN_ROOT}/scripts/config-add.sh ignore --repo <repo_root>`

   Always pass `repo_root`, not the worktree path. A non-zero exit means nothing
   was written: show its message and stop. It refuses a repo already declared
   under another world, and a config file it cannot parse.
4. **Bootstrap.** For a new world, create the world folder under
   `root_collection` with `INDEX` only. Then bootstrap the project folder
   (`INDEX`, `Specs`, `Plans`, `Tasks`) as in Bootstrap above. Skip this for
   "do not persist".
5. **Confirm.** Re-run `resolve-context.sh`. It must now show `world_source` =
   `config` and a `kb_path`, or `ignored` = true. Report the result in one line.

If Outline is not connected: say world discovery is unavailable, and offer only
"New world" (typed name) or "Skip for this session". A typed world may still be
recorded with `config-add.sh`, but write nothing to Outline; bootstrap happens on
the first write once Outline is back. "Skip for this session" writes nothing
anywhere, and the session works without persistence.

## The persisted work record

Persist structured state, not a transcript. The record at `record_path` holds
**current state only** and stays under about 4,000 characters. History never goes
into it. Its body has these sections, in this order, each a `##` heading:

```
Repo: <project> (<world>), branch <branch>, worktree <worktree>
Last updated: YYYY-MM-DD

## Objective          objective and acceptance criteria
## Status             one of active, blocked, handoff, complete
## Decisions          current decisions, one line each
## Verified facts     with evidence; inferred or unverified items labelled as such
## Blockers           or "None"
## Next action        one concrete step
## Checkpoints        links to the latest 5 checkpoint docs, newest first
## Related            [[doc-title]] links to Spec, Plan and other docs
```

Each section is a summary that is **rewritten**, not grown. When a fact, decision
or blocker is superseded, replace it; the old wording lives in the checkpoint
history. Changed files, test output and step-by-step evidence belong in the
checkpoint doc, not in the record.

**Compacting an oversized record.** A record found over about 4,000 characters
(older records grew before this rule) is compacted in the same write, never left
as is to protect its history. Moving is not deleting:

1. Create a checkpoint child titled `<YYYY-MM-DD> history before compaction` and
   copy the superseded text into it verbatim, with the back-link `Record: [[<slug>]]`.
2. Rewrite the record's sections to current state only, under the limit, and link
   that child first in `## Checkpoints`.
3. Report the compaction in one line: old and new size, and the child's title.

Distinguish **verified / inferred / unverified / blocked** claims explicitly. Never
present an unverified claim as verified.

### Checkpoint history: child documents

Each checkpoint, handoff or completion writes one short child document under the
record: `create_document` with `parentDocumentId` = the record's id and title
`<YYYY-MM-DD> <short title>` (for example `2026-10-16 stop guard tests green`).
Its body holds what happened at that point: changed files, commands run and their
decoded outcomes, decisions taken, and a back-link `Record: [[<slug>]]`. Keep it
short; it is a log entry, not a second record. Never append checkpoint text to the
record itself.

### Writing cheaply

`update_document` returns the whole document, so every write re-reads the body
into the session. Keep it small:

- Update the record with `editMode: "patch"`: `findText` is the exact current
  text of one state section (from the heading to the next heading), `text` is its
  new version. Patch only the sections that changed (usually Status, Next action,
  Checkpoints). Use `replace` only when creating the body or repairing a record
  whose sections no longer match the layout above, and then trim it under the size
  limit in the same write.
- The write response already contains the updated body. Check the change there.
  Do not `fetch` the record again just to verify a write you already have a
  response for.
- Keep the last body you read or wrote in mind and patch from it; `fetch` again
  only when another session may have changed the record since.

## Idempotency

The record identity is `project` + `task_slug`, realised as the doc at
`record_path`. Before creating, `list_documents` under `tasks_path` and match the
title to the slug. If it exists, `update_document` it. A repeated checkpoint updates
the same record and never duplicates. Never use a timestamp as document identity.

A checkpoint doc is history, not identity: it is always found through its parent
record. Before creating one, list the record's children; if a child with the same
`<YYYY-MM-DD> <short title>` already exists (a retried write), update that child
instead of creating a second one.

## Status and the `Tasks` parent

The record status and the flag in the `Tasks` parent child-list differ. Map them:

| Record status | `Tasks` flag |
|---|---|
| `active` | `doing` |
| `blocked` | `blocked` |
| `handoff` | `doing` |
| `complete` | `done` |

The flag has no field of its own. It is the text in brackets on the record's line in
the `Tasks` parent document body, one line per record:

```
* **<task-slug>** (<flag>, <YYYY-MM-DD>): <one-line summary>
```

A new record always gets this line, and each status change patches it
(`editMode: "patch"`, `findText` = the record's current line) with the new flag and
date. If the line is missing, add it to the parent's task list; if the parent uses
another list layout, keep that layout and change only the flag word. If the parent
is missing, create it through Bootstrap, then add the record.

## Lifecycle (maps to the commands)

- **load**: resolve identity; find the record at `record_path`; read it plus the
  project `INDEX` and linked docs before substantive work; return a concise
  current-state summary. Read checkpoint child docs only when the record's state
  is not enough. If Outline is unavailable, say persistence is unavailable and
  stop the load. Load stays read-only: if the collection, folder or record does
  not exist yet, say which one is missing and that the first write will create
  it. Never report a missing target as "no prior state" without naming it.
- **start**: bootstrap if needed; create or update `record_path` with objective, acceptance criteria,
  repo, worktree, branch; link related Specs/Plans/existing docs. Update the `Tasks`
  parent child-list.
- **checkpoint**: after a meaningful *verified* milestone, create one checkpoint
  child doc (changed files, evidence, tests), then patch the same record's state
  sections: Status, Decisions, Verified facts, Blockers, Next action, Checkpoints,
  `Last updated:`. Never a new record, never appended history.
- **handoff**: write a compact handoff state when the session ends, is blocked or is
  transferred: a checkpoint child doc with what is done and what remains, and a
  patch of the record's state sections; status `handoff` or `blocked`; label
  verified / inferred / unverified / blocked.
- **complete**: record the real completion result: verification commands and
  their outcomes go in a final checkpoint child doc; the record's Status becomes
  `complete` and Next action `None`. Closed items move out of the record into that
  child doc rather than being deleted. Do not mark complete merely because files
  changed.
- **dry-run**: show the intended read or write (target collection/folder/doc, the
  fields, the redacted body) without calling any write tool.
- **off**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/persistence-state.sh off` disables the
  automatic SessionStart rule and the Stop guard below without removing the plugin;
  `... on` re-enables both.
- **setup**: run Onboarding (above) for the current repo.

A `Stop` hook (`scripts/stop-guard.sh`) also runs when a turn ends. If work was
shipped (a git commit or push, `gh pr create` or `merge`, a release, publish or
deploy) since the last Outline write in the transcript, it blocks the stop once and
asks the model to run this skill (checkpoint, handoff or complete) before finishing. For an
unresolved repo it asks for Onboarding (`/setup`) first. It never blocks twice in a
row, it never blocks for an ignored repo, and it never fires when persistence is off
or in a non-interactive run (`claude -p`, SDK). After a block or an Outline write it
stays quiet for a cooldown (90 minutes by default, `WORKLOG_STOP_COOLDOWN_MIN`).
Edits alone and long read-only runs never trigger it. A decline ("trivial, stopping")
is remembered per session, so the same already-shown work is not blocked again on
the next turn; only new work after the decline triggers another block.

## When to write vs. not

Write at task start, meaningful verified checkpoints, decisions, blockers, handoff and
completion — **not on every tool call**. Don't write trivia obvious from code, or
duplicate existing content (update instead).

## Cross-linking

No orphan docs. Every record links its Plan/Spec where they exist; every doc it
depends on gets a back-link. Add a `## Related` section with `[[doc-title]]` links.
Update the `Tasks` parent every time a record is created, renamed, status-changed or
closed. Never expose the operator's Outline collection names or MCP server URL
in public artifacts, commits or external messages.
