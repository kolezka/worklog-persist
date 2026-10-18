---
name: dry-run
description: Show the intended Outline read or write without changing anything.
---

Run the worklog-persist skill in **dry-run** mode.

1. Resolve identity via `scripts/resolve-context.sh`.
2. Show exactly what a real `/load`, `/start`, `/checkpoint`, `/handoff` or `/complete` would do:
   - the resolved `world` (and `world_source`), `kb_path` and `record_path`;
   - a missing `root_collection` collection and any bootstrap docs that would be created;
   - whether it would `create_document` or `update_document` (based on a read-only `list_documents` match);
   - for a checkpoint, handoff or complete: the checkpoint child doc it would create, and the record sections it would patch;
   - the full record body **after** running `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/redact.py`, so redaction is visible.
3. Call NO write tool. `list_documents` / `fetch` (read-only) are allowed to determine create-vs-update.

Output the plan only. Make no mutation to Outline.
