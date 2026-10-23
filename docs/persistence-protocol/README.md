---
block: persistence-protocol
doc: README
verified_against: fcd9e31
verified_on: 2026-10-23
owns: [skills/, commands/, scripts/resolve-context.sh, scripts/resolve_context.py, scripts/config-add.sh, scripts/config_add.py, scripts/redact.py]
depends_on: [packaging]
---

# persistence-protocol

What to read, write, redact and never hardcode. This block is the plugin's
operational contract: the skill text, the eight slash commands that trigger it,
and the helper scripts that resolve identity, write the config and strip
secrets.

It never talks to Outline directly. It writes prompt text that tells the agent
which MCP tools to call and how to shape the record; the actual connection (the
`outline` server definition, its URL, its auth headers) belongs to
[`packaging`](../packaging/README.md), see
[`packaging/CONTRACTS.md`](../packaging/CONTRACTS.md). It does not own the
SessionStart hook or the on/off state file either; that is
[`session-hook`](../session-hook/README.md).

## Boundary

Owned: `skills/worklog-persist/SKILL.md`, the eight lifecycle files in `commands/`
and `commands/show.md`,
`scripts/resolve-context.sh`, `scripts/resolve_context.py`,
`scripts/config-add.sh`, `scripts/config_add.py`, `scripts/redact.py`.

Also owned, though it lives outside the repo: the format of the plugin config
file that the resolver reads and `config-add.sh` writes. See
[`CONTRACTS.md`](CONTRACTS.md#plugin-config-file).

Not owned, referenced only: `.mcp.json` (packaging), `scripts/persistence-state.sh`
and `hooks/` (session-hook), `tests/` (verification, cited here only as
`enforcement:` evidence per [`CONVENTIONS.md`](../CONVENTIONS.md)).

## What it does

`skills/worklog-persist/SKILL.md::"This skill is the operational contract"`
[verified]. The eight commands
(`commands/load.md`, `commands/start.md`, `commands/checkpoint.md`,
`commands/handoff.md`, `commands/complete.md`, `commands/dry-run.md`,
`commands/off.md`, `commands/setup.md`) are thin entry points that each say "Run the worklog-persist
skill's **\<verb\>** step", for example
`commands/checkpoint.md::"Run the worklog-persist skill's **checkpoint** step."`
[verified]. None of the eight command files names an `mcp__` tool prefix; only
`skills/worklog-persist/SKILL.md::"mcp__outline__*"` and
`skills/worklog-persist/SKILL.md::"mcp__plugin_worklog-persist_outline__*"` do,
so the dual-prefix contract lives in exactly one place [verified].

Identity and the Outline address come from `scripts/resolve-context.sh`, which
runs `scripts/resolve_context.py::main()` over git and the plugin's own YAML
config [verified]. The config is written only by `scripts/config-add.sh`, which
runs `scripts/config_add.py::main()` during onboarding [verified]. Secrets are stripped by `scripts/redact.py::redact()` before
any write. See [`CONTRACTS.md`](CONTRACTS.md) for both.

```mermaid
flowchart LR
    Cmds["/load /start /checkpoint /handoff /complete /dry-run /off /setup"] --> Skill["skills/worklog-persist/SKILL.md"]
    Skill --> Resolve["scripts/resolve-context.sh"]
    Skill --> Redact["scripts/redact.py"]
    Skill -->|onboarding| Add["scripts/config-add.sh"]
    Add --> Config[("config.yaml")]
    Config --> Resolve
    Resolve -->|world| World{"config, $WORKLOG_WORLD or UNRESOLVED"}
    Skill -->|ToolSearch| Prefix{"mcp__outline__* or\nmcp__plugin_worklog-persist_outline__*"}
    Prefix --> Outline[("Outline MCP server")]
    Redact -->|"<REDACTED:kind>"| Outline
```

## Files in this block

| File | Holds |
|---|---|
| [`CONTRACTS.md`](CONTRACTS.md) | The command set, the dual MCP prefix, identity resolution, the config file and its writer, onboarding, redaction, record identity |
| [`INVARIANTS.md`](INVARIANTS.md) | Behaviours the skill text requires and what breaks without them |
| [`GAPS.md`](GAPS.md) | Where only the model, not code, enforces the protocol |
| [`OPERATIONS.md`](OPERATIONS.md) | The eight entry points, where identity and state come from, stuck states |
| [`DECISIONS.md`](DECISIONS.md) | Why the contract lives in one skill file, and other recorded choices |

Read [`../CONVENTIONS.md`](../CONVENTIONS.md) and the block map in
[`../README.md`](../README.md) first.
