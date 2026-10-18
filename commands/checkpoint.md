---
name: checkpoint
description: Update the same Outline task record after a verified milestone.
---

Run the worklog-persist skill's **checkpoint** step.

1. Availability check; resolve identity; locate the existing record at `record_path`. If the record, its folder or the collection is missing, run **start** first (it bootstraps them); never skip the write. Never create a second record for the same work item.
2. Write the history first: `create_document` one child of the record (`parentDocumentId` = the record's id), title `<YYYY-MM-DD> <short title>`, a short body with changed files, commands run and their decoded outcomes, decisions, and a back-link `Record: [[<slug>]]`. If a child with that exact title already exists, update it instead. Never append this text to the record.
3. Then update the record's current state only, with `editMode: "patch"` per changed section (`findText` = the section's exact current text): Status, Decisions, Verified facts, Blockers, Next action, Checkpoints (add the new child link, keep the latest 5), `Last updated:`. Keep status `active` (or set `blocked` with the blocker, and set the `Tasks` parent flag to `blocked`). Keep the record under about 4,000 characters.
4. Label each claim **verified / inferred / unverified / blocked**. Only record a milestone that was actually verified.
5. Redact via `scripts/redact.py` before each write. The record is updated in place with `update_document` (idempotency key = project + task slug); `create_document` is only for the checkpoint child.

Confirm each write from its Outline response, which already holds the new body. Do not `fetch` the record again just to verify.
