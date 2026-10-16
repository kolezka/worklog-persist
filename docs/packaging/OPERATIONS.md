---
block: packaging
doc: OPERATIONS
verified_against: 7d87d3b
verified_on: 2026-10-16
---

# Operations

Entry points this block exposes, how to undo them, and where things get stuck.
State paths and the automatic-persistence kill switch belong to
[session-hook](../session-hook/README.md); this page only covers the
plugin-level install lifecycle.

## Entry points

| Command | Effect |
|---|---|
| `./install.sh` | Dry run. Prints `PLAN:` lines, changes nothing [verified]. |
| `./install.sh --check` | Runs `` `install.sh::check_structure()` ``; no `claude` CLI needed [verified]. |
| `./install.sh --apply` | Registers the marketplace and installs the plugin, asking `y/N` per step [verified]. |
| `./install.sh --apply --yes` | Same, non-interactive [verified]. |
| `./install.sh --apply --enable` | Re-enables an installed, disabled plugin [verified]. |
| `./install.sh --apply --disable` | Disables the plugin without removing it [verified]. |
| `./install.sh --apply --uninstall` | Removes the plugin via the `claude` CLI [verified]. |
| `make plan` | Alias for `./install.sh` (dry run) [verified]. |
| `make install` | Guards the worktree, then runs `./install.sh --apply` [verified]. |
| `make check` | `test` + `test-sh` + `./install.sh --check` [verified]. |
| `make test` | `` `Makefile::"Python suite"` ``: `env -u FORCE_COLOR uv run pytest -q` [verified]. |
| `make test-sh` | Runs every `tests/*.sh` suite; not collected by `make test` [verified]. |
| `make lint` | `` `Makefile::"shellcheck every shell file"` ``, at warning severity [verified]. |
| `make live` | Opt-in reachability probe against the real Outline endpoint [verified]. |

`install.sh`'s own usage line is the source of truth for flags:
`` `install.sh::usage()` `` [verified].

## Uninstalling this plugin

Run `./install.sh --apply --uninstall` (or `--apply --yes --uninstall` for
non-interactive), which calls `` `install.sh::"claude plugin uninstall"` ``
[verified]. There is no `make uninstall` target (see [`GAPS.md`](GAPS.md)).

## Kill switch, at the plugin level

`./install.sh --apply --disable` turns the whole plugin off at the `claude`
CLI level. This is a different, coarser switch than the automatic-persistence
off switch documented in
[`session-hook/OPERATIONS.md`](../session-hook/OPERATIONS.md), which disables
only the SessionStart reminder without uninstalling or disabling the plugin
itself.

## Stuck states

**A same-named plugin from another marketplace is already registered.**
`` `install.sh::plugin_present()` `` only recognizes
`worklog-persist@worklog-persist-marketplace`, so `install.sh` still plans to
install this plugin's own entry even when `worklog-persist` already exists
under a different marketplace name [verified]. Whether the `claude` CLI itself
then errors, warns, or silently keeps two entries is not exercised by this
repo's tests [assumption]. If installation fails at that point, uninstall the
foreign entry first: `claude plugin uninstall worklog-persist@<other
marketplace>`.

**The old `outline-persist` plugin is still installed.** This plugin was
renamed from `outline-persist`; the old plugin, marketplace and state
directory do not migrate automatically. Uninstall it explicitly
(`` `README.md::"claude plugin uninstall outline-persist@<marketplace>"` ``)
[verified], and if automatic persistence had been turned off under the old
name, re-run the off switch once after installing this plugin, since
`` `README.md::"off-state file does not"` `` migrate [verified].

**`--apply` refuses with `REFUSING`.** This means the checkout is a linked git
worktree (`` `install.sh::require_main_checkout()` ``). Re-run the same
command from the main checkout, not the worktree; there is no flag to
override this [verified].

**A different Outline instance is needed.** `.mcp.json`'s URL is fixed in this
repo; see [`GAPS.md`](GAPS.md) for what is and is not known about overriding
it.
