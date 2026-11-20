---
name: setup
description: Route this repo to an Outline world, or mark it as not persisted.
---

Run the worklog-persist skill's **Onboarding** step.

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-context.sh`. If `world_source` is `config` or `ignored` is true, report that the repo is already set up and stop. If `config_error` says the file is unreadable or malformed, report it with `config_path` and stop.
2. Availability check. If Outline is connected, `list_documents` directly under `root_collection`; each top-level document title is a world, and so is each key of the resolver's `world_collections`. Never hardcode or cache world names.
3. Ask one question: one of the discovered worlds, "New world" (the user types the name), or "Do not persist this repo". Confirm the project name in the same question (default: the resolver's `project`). If Outline is not connected, say discovery is unavailable and offer only "New world" or "Skip for this session".
4. Record the answer with `bash ${CLAUDE_PLUGIN_ROOT}/scripts/config-add.sh project --world <World> --name <project> --repo <repo_root>` or `... ignore --repo <repo_root>`. Never edit the config by hand. On a non-zero exit, show the message and stop.
5. If Outline is connected: for a new world create its folder with `INDEX` only, then bootstrap the project folder (`INDEX`, `Specs`, `Plans`, `Tasks`). Pipe every body through `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/redact.py`.
6. Re-run `resolve-context.sh` and confirm `kb_path` is set, or `ignored` is true.

Do not claim the repo is set up unless step 6 shows it.
