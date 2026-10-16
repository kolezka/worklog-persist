---
name: handoff
description: Write a compact handoff state when the session ends, is blocked, or is transferred.
---

Run the worklog-persist skill's **handoff** step.

1. Availability check; resolve identity; locate the existing record at `record_path` (update it, do not duplicate).
2. Create one checkpoint child doc under the record (title `<YYYY-MM-DD> handoff`, or `<YYYY-MM-DD> blocked`): what is done, what remains, open questions, and a back-link `Record: [[<slug>]]`.
3. Patch the record's state sections with `editMode: "patch"`: Status (`handoff` or `blocked`), Blockers, Next action (the exact next step), Checkpoints, `Last updated:`. Keep it current state only, under about 4,000 characters.
4. Clearly separate **verified**, **inferred**, **unverified** and **blocked** claims so the next session can trust the record.
5. Redact via `scripts/redact.py`; set the `Tasks` parent flag (`handoff` maps to `doing`, `blocked` to `blocked`).

Report the write only after the Outline response confirms it. The response already holds the body; do not `fetch` again to verify.
