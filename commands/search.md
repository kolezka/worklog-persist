---
name: search
description: Search Outline work records and available conversation history by day, date range or last N days.
---

Run the worklog-persist skill's **search** step with the user's arguments.

Examples: `/search --on 2026-11-09`, `/search --from 2026-11-01 --to 2026-11-09`,
`/search --last-days 7 --timezone Europe/Warsaw`. Optional text narrows the results;
without text, browse the chosen period. Default source is both Outline and
conversation history, scoped to the current project/workspace.

Read-only. Do not bootstrap, checkpoint or change any source. Report unavailable
sources and incomplete pagination, never turn them into "no matches".
