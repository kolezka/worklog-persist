---
block: packaging
doc: CONTRACTS
verified_against: fcd9e31
verified_on: 2026-10-23
---

# Contracts

Durable interfaces this block keeps in shape. See
[`CONVENTIONS.md`](../CONVENTIONS.md) for the citation and evidence rules.

## Plugin and marketplace identity

`.claude-plugin/plugin.json` declares name `worklog-persist`
(`` `.claude-plugin/plugin.json::"worklog-persist"` ``) [verified].
`.claude-plugin/marketplace.json` declares marketplace name
`worklog-persist-marketplace` and lists a plugin entry named `worklog-persist`
with `source: "./"`, so the marketplace resolves to this checkout's root
(`` `.claude-plugin/marketplace.json::"worklog-persist-marketplace"` ``)
[verified]. `install.sh::check_structure()` fails the build if `plugin.json`'s
name is not exactly `worklog-persist` or if `marketplace.json` does not list it
[verified].

enforcement: `` `install.sh::check_structure()` `` (only at `--check` time), plus
  `` `tests/test_structure.sh::"structure valid and idempotent"` ``.

`.claude-plugin/plugin.json::"types"` points at `types/index.d.ts`, the native
panel's state contract, which `claude plugin validate` holds the hooks module to
[verified: uncommitted worktree, not at the pin]. The contract itself belongs to
[session-hook](../session-hook/CONTRACTS.md#native-worklog-panel).

enforcement: `` `Makefile::test-native` `` runs `claude plugin validate .`; not
  part of `make check`.

## Install CLI: dry-run unless told otherwise

`install.sh` with no flags only prints a plan, prefixed `PLAN:`, and mutates
nothing (`` `install.sh::step()` ``) [verified]. `--apply` runs the plan; without
`--yes` each mutating step asks `y/N` on stdin and a closed or non-`y` stdin
aborts before running anything (`` `install.sh::step()` ``) [verified]. `--yes`
skips the prompt. `--check` runs `` `install.sh::check_structure()` `` and needs
no `claude` binary at all [verified].

enforcement: `` `tests/test_install.sh::"default run is read-only"` `` and
  `` `tests/test_install.sh::"--apply without consent aborts"` ``.

## Worktree guard

`` `install.sh::require_main_checkout()` `` compares `git rev-parse --git-dir`
against `git rev-parse --git-common-dir` for `$ROOT` and exits 1 before any
mutation when they differ, because `claude plugin marketplace add` records
`$ROOT` as a path, and a linked worktree's path is deleted with its branch, as
the function's own comment explains
(`` `install.sh::"records $ROOT"` ``) [verified]. The `Makefile`
repeats the same check independently for `make install`
(`` `Makefile::require_main_checkout` ``) [verified].

enforcement: `` `tests/test_install.sh::"--apply refused from linked worktree"` ``
  and the positive control `` `tests/test_install.sh::"--apply allowed from main checkout"` ``.

## Installed-state detection

`` `install.sh::marketplace_present()` `` and `` `install.sh::plugin_present()` ``
grep `claude plugin marketplace list` / `claude plugin list` output for the
exact strings `$MARKET` and `${PLUGIN}@${MARKET}` [verified]. A plugin named
`worklog-persist` registered under a different marketplace does not match
`${PLUGIN}@${MARKET}`, so `install.sh` still plans to install this plugin's own
marketplace-qualified copy rather than treating the foreign one as sufficient
[verified].

enforcement: `` `tests/test_install.sh::"foreign marketplace ignored"` ``.

## Structure validator

`` `install.sh::check_structure()` `` is a standalone Python check
(`--check`, or `make check`) that validates: `plugin.json` name, `marketplace.json`
membership, `hooks/hooks.json` wraps `SessionStart` under a top-level `hooks`
key, `.mcp.json` defines exactly the server list `["outline"]`, the eight
command files `load`, `start`, `checkpoint`, `handoff`, `complete`, `dry-run`,
`off`, `setup` exist under `commands/`, `skills/worklog-persist/SKILL.md` exists,
and `scripts/session-start.sh`, `scripts/resolve-context.sh`,
`scripts/resolve_context.py`, `scripts/config-add.sh`, `scripts/config_add.py`,
`scripts/persistence-state.sh`, `scripts/redact.py` all exist [verified]. It is
never invoked automatically by `` `install.sh::do_install()` ``; a plain
`--apply` does not run it [verified].

enforcement: `` `install.sh::check_structure()` `` itself (only when `--check`
  is passed, or via `make check`); no invariant forces it to run before
  `--apply`.

## MCP server registration

`.mcp.json` defines exactly one server, `outline`, `type: "http"`, with `url`
and `headers` sourced from environment placeholders only:
`` `.mcp.json::"${OUTLINE_MCP_URL}"` ``,
`` `.mcp.json::"CF-Access-Client-Id"` ``,
`` `.mcp.json::"CF-Access-Client-Secret"` ``, and
`` `.mcp.json::"${OUTLINE_API_TOKEN}"` `` [verified]. No operator's Outline
instance URL is named in this file; an operator sets `OUTLINE_MCP_URL` before
first use, documented in `` `README.md::"OUTLINE_MCP_URL"` `` [verified].
`check_structure()` rejects any `.mcp.json` whose server list is not exactly
`["outline"]` [verified].

enforcement: `` `tests/test_structure.sh::"single outline MCP server"` ``,
  `` `tests/test_structure.sh::"credentials are env placeholders only"` `` and
  `` `tests/test_structure.sh::"server url is an env placeholder"` ``.

## MCP tool-prefix derivation

Packaging fixes the two inputs Claude Code combines into an MCP tool prefix:
the plugin name `worklog-persist` (`.claude-plugin/plugin.json`) and the
server name `outline` (`.mcp.json`). When the plugin's bundled server is what
loads, its tools are exposed as `mcp__plugin_worklog-persist_outline__*`; a
user, project or local `.mcp.json` that also defines an `outline` server at
the same URL is deduplicated by Claude Code to the bare
`mcp__outline__*` prefix instead [inferred from the commit fixing this, whose
message states both prefixes explicitly]. The literal plugin-scoped prefix is
attested inside the shipped skill file itself:
`` `skills/worklog-persist/SKILL.md::"mcp__plugin_worklog-persist_outline__"` ``
[verified]. This is the contract [persistence-protocol](../persistence-protocol/README.md)'s
skill has to satisfy; see
[`persistence-protocol/CONTRACTS.md`](../persistence-protocol/CONTRACTS.md) for
how it searches both prefixes.

enforcement: convention on the packaging side (nothing in this block asserts
  the naming rule itself); the consumer-side check lives in
  `` `tests/test_structure.sh::"skill handles both MCP tool prefixes"` ``, owned
  by [verification](../verification/README.md).

## Makefile entry points

`` `Makefile::"Register the marketplace and install the plugin"` `` describes
`install`; `` `Makefile::"would run. Changes nothing"` `` describes
`plan`; `` `Makefile::"Everything offline"` `` describes `check`, which runs
`test`, `test-sh`, then `` `./install.sh --check` `` [verified]. `make live` runs
`` `Makefile::"WORKLOG_PERSIST_LIVE=1 bash tests/test_live_outline.sh"` ``, an
opt-in reachability probe against the real Outline endpoint [verified].
`make test-native` runs `claude plugin validate .` and `claude plugin test .`,
and fails with a message when the `claude` CLI is missing instead of skipping
(`` `Makefile::"native tests did not run"` ``) [verified: uncommitted worktree, not at the pin].
`make typecheck-native TYPES=<claude-code.d.ts>` type-checks `hooks/`, `types/`
and the native tests against that build's declarations with
`pnpm --package=typescript@5.6.3 dlx tsc`, and fails when `TYPES` is not a file
or `pnpm` is not on `PATH` (`` `Makefile::"pnpm not found; the type-check did not run"` ``) [verified: uncommitted worktree, not at the pin]. Neither is part of `make check`, because both
need the `claude` CLI and `check` does not.

enforcement: `` `Makefile::help` `` lists every target from its own `##`
  comments, so an undocumented target cannot silently exist; there is no test
  that runs every target end to end.

## Python toolchain

`pyproject.toml` declares `requires-python = ">=3.11"`, a `dev` dependency
group of `pytest` only, and `` `pyproject.toml::"package = false"` `` under
`[tool.uv]`, meaning this repo is never built or published as an installable
Python package [verified]. `` `pyproject.toml::testpaths` `` scopes pytest to
`tests/` [verified]. `uv.lock` pins the resolved dependency graph
(`` `uv.lock::iniconfig` ``) [verified].

enforcement: convention; no target checks that `uv.lock` is still current
  for `pyproject.toml` (see [`GAPS.md`](GAPS.md)).

## Ignored paths

`.gitignore` excludes `` `.gitignore::"__pycache__/"` ``,
`` `.gitignore::"*.pyc"` ``, `` `.gitignore::".pytest_cache/"` ``,
`` `.gitignore::".venv/"` ``, and
`` `.gitignore::".claude/tdd-guard/data/*.json"` `` [verified].

enforcement: convention; nothing fails a commit that adds one of these paths
  with `git add -f`.
