---
name: show
description: Open the native worklog panel for the current project.
---

The native worklog panel opens when this plugin's hooks module is loaded, in a
Claude Code build with Mods. That module answers this command itself, so if you
are reading this, the panel is not loaded in this session.

Tell the user that in one sentence, and that `/worklog-persist:load` gives a
read-only summary of the current task instead. Do not call any Outline tool for
this command, and do not write anything.
