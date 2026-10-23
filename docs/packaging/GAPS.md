---
block: packaging
doc: GAPS
verified_against: b92a027
verified_on: 2026-10-23
---

# Gaps

Debt and unenforced boundaries in this block. A change here is free to close
any of these without touching a contract or an invariant.

## Nothing validates that `OUTLINE_MCP_URL` is actually set

`.mcp.json` now reads the endpoint from `` `.mcp.json::"${OUTLINE_MCP_URL}"` ``
[verified], so no fork is needed to point the plugin at a different Outline
instance, closing the former "URL is hardcoded" gap. Nothing in this repo
checks that the operator has actually exported `OUTLINE_MCP_URL` before a
session starts: `tests/test_structure.sh::"server url is an env placeholder"`
only proves the manifest never hardcodes a real endpoint again, not that the
variable resolves to one at run time [verified]. An unset variable is a
connection failure the skill's own availability check
([`../persistence-protocol/CONTRACTS.md`](../persistence-protocol/CONTRACTS.md#availability-precondition))
is expected to surface, not a crash, but that path is not exercised by any
test in this repo [inferred].

## Whether an installed plugin is a live path or a cached copy is unverified

`claude plugin marketplace add` registers `$ROOT` as a path
(`` `install.sh::require_main_checkout()` `` depends on that fact) [verified],
but nothing in this repo's code or tests shows whether `claude plugin install`
then reads the plugin's files from that path live on every session, or copies
them into a cache at install time. If it caches, editing a tracked file after
installing requires an explicit reinstall or update before the change takes
effect; if it reads live, it does not. `AGENTS.md`'s installer guidance
(`` `AGENTS.md::"linked worktree"` ``) is consistent with either model and does
not resolve it [assumption].

## `check_structure()` is not run before `--apply`

A plain `./install.sh --apply` (or `--apply --yes`) does not call
`` `install.sh::check_structure()` `` first; only `--check` and, through it,
`make check` do [verified]. A broken plugin tree (a missing command file, a
malformed `.mcp.json`) can be installed via `claude plugin install` without
this repo's own validator ever running against it.

## `plugin_present()` / `marketplace_present()` use unanchored substring match

Both use `grep -q` on free-text CLI output without `^`/`$` anchors
(`` `install.sh::marketplace_present()` ``, `` `install.sh::plugin_present()` ``)
[verified]. A hypothetical entry that contains `${PLUGIN}@${MARKET}` as a
substring of a longer name would false-positive as "already installed". No
test constructs such a name, so this is unexercised rather than proven safe
[inferred].

## No `make` target for enable, disable or uninstall

The `Makefile` exposes `plan` and `install` but not `--enable`, `--disable`
or `--uninstall`; those are reachable only by calling `install.sh` directly,
as documented in the top-level `README.md`
(`` `README.md::"install.sh --apply --uninstall"` ``) [verified]. Minor
discoverability gap for someone who only ever runs `make`.

## `uv.lock` freshness is not checked by any target

No `Makefile` target runs `uv lock --check` or equivalent. If
`pyproject.toml`'s dependencies changed without re-running `uv lock`, `make
test` and `make check` would still resolve against a stale lock file and
nothing would fail loudly [inferred from reading every `Makefile` target and
finding no such check].
