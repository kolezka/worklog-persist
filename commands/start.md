---
name: start
description: Create or update the Outline task record at the start of a work item.
---

Run the worklog-persist skill's **start** step.

1. Availability check; resolve identity via `scripts/resolve-context.sh <slug>` (run `/setup` first if world is `UNRESOLVED`; ask once if the repo is `ignored` or the slug is unclear).
2. Bootstrap if the `root_collection` collection, `kb_path` or its children are missing: create a missing collection with `create_collection`, a world folder gets `INDEX` only, a project folder gets `INDEX`, `Specs`, `Plans`, `Tasks`. Check each before creating it, and report what was created. A missing target is created, never skip the write.
3. `list_documents` in `tasks_path` and match the task slug — **prefer updating the existing record over creating a duplicate** (idempotency key = project + task slug).
4. Compose the record body in the skill's record layout (current state only, under about 4,000 characters): repo, worktree, branch, `Last updated: YYYY-MM-DD`, then `## Objective` (with acceptance criteria), `## Status` (`active`), `## Decisions`, `## Verified facts`, `## Blockers`, `## Next action`, `## Checkpoints`, and `## Related` linking the Spec/Plan and related docs. For an existing record, patch only the sections that change (`editMode: "patch"`).
5. Pipe the body through `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/redact.py` before writing.
6. `create_document` (title `<task-slug>`, no leading H1, parent `tasks_path`) or `update_document`. Then add the record's line in the `Tasks` parent body, `* **<task-slug>** (doing, <YYYY-MM-DD>): <one-line summary>` (see the skill's "Status and the `Tasks` parent").

Never write secrets. Do not claim success unless the Outline response confirms the write.
