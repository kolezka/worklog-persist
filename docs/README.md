---
block: _root
doc: README
verified_against: 3425d99
verified_on: 2026-10-16
unassigned: [README.md, AGENTS.md, .claude/, .ai/, .gitkeep, .gitattributes, .repo-intel.json, docs/]
---

# docs: the plugin by building block

What `worklog-persist` is, cut into the blocks it is built from.

Read [`CONVENTIONS.md`](CONVENTIONS.md) before you write here.

---

## What this plugin is

A Claude Code plugin that keeps the state of active work in Outline, so the next
session can continue it. It has three moving parts: a skill and eight slash
commands that tell the agent what to read and write, a SessionStart hook that
reminds the agent of the rule, and an installer that registers the plugin with
the `claude` CLI.

The plugin never calls Outline itself. Every read and write is an agent call to
the `outline` MCP server, driven by the skill text. The tool prefix is
`mcp__outline__*` or `mcp__plugin_worklog-persist_outline__*`; see
[`persistence-protocol/CONTRACTS.md`](persistence-protocol/CONTRACTS.md).

```mermaid
flowchart LR
    Install["install.sh --apply"] -->|claude plugin install| CLI[("claude CLI registry")]
    CLI --> Session["Claude Code session"]
    Hook["SessionStart hook"] -->|additionalContext| Session
    Skill["skill + /commands"] --> Session
    Session -->|outline MCP tools| Outline[("Outline wiki")]
    Session -. redact.py, resolve-context.sh .-> Session
```

---

## The block map

| Block | What it owns |
|---|---|
| [`packaging/`](packaging/) | Plugin and marketplace manifests, the MCP server entry, the installer, the `Makefile` |
| [`session-hook/`](session-hook/) | The SessionStart hook and the off switch that gates it |
| [`persistence-protocol/`](persistence-protocol/) | The skill, the eight commands, identity resolution, the config writer and secret redaction |
| [`verification/`](verification/) | The test suites, what each one proves, and what nothing proves |

---

## How to read a block

Every block folder holds the same files:

- **`README.md`**: what it is, its boundary, its file inventory, one diagram
- **`CONTRACTS.md`**: durable interfaces, each with an `enforcement:` field
- **`INVARIANTS.md`**: behaviours that must hold, each with the defect it prevents
- **`GAPS.md`**: debt and unenforced boundaries; what a change may fix
- **`OPERATIONS.md`**: entry points, state paths, kill switches, stuck states
- **`DECISIONS.md`**: optional; why it is shaped this way

---

## Unassigned on purpose

The `unassigned:` front matter above lists files no block owns:

| Path | Why |
|---|---|
| `README.md` | The front door. It links here and does not restate block facts |
| `AGENTS.md`, `.claude/` | Rules for working in this repo, not a part of the plugin |
| `.ai/` | Session plans and lessons |
| `.gitkeep` | Placeholder from the repo template |
| `.gitattributes`, `.repo-intel.json` | Repo tooling config for codegraph and graphify, not a part of the plugin |
| `docs/` | This tree. It describes the plugin; it is not a component of it |
