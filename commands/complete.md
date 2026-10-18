---
name: complete
description: Record the real completion result of a work item in Outline.
---

Run the worklog-persist skill's **complete** step.

1. Availability check; resolve identity; locate the existing record at `record_path`. If the record, its folder or the collection is missing, run **start** first (it bootstraps them); never skip the write.
2. Create a final checkpoint child doc under the record (title `<YYYY-MM-DD> complete`): the verification commands run and their decoded outcomes, links to the merged commit/PR/pipeline, closed items, and a back-link `Record: [[<slug>]]`.
3. **Do not mark complete merely because files changed.** Only claim completion for acceptance criteria that were verified; list any that were not.
4. Patch the record with `editMode: "patch"`: Status `complete`, Next action `None`, Checkpoints, `Last updated:`. Closed items move to the child doc instead of being deleted. Redact via `scripts/redact.py`; patch the record's line in the `Tasks` parent body to `(done, <YYYY-MM-DD>)`. A record over about 4,000 characters is compacted first (skill: "Compacting an oversized record").

Confirm from the Outline response before reporting completion. Do not `fetch` the record again just to verify.
