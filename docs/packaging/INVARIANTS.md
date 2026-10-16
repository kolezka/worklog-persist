---
block: packaging
doc: INVARIANTS
verified_against: 7c67f29
verified_on: 2026-10-16
---

# Invariants

Numbered behaviours this block must keep. Each names the defect it blocks. See
[`CONVENTIONS.md`](../CONVENTIONS.md).

1. **A bare `./install.sh` run never mutates anything.** `` `install.sh::step()` ``
   only prints `PLAN:` lines until `--apply` is given [verified]. Blocks: a
   curious or scripted run silently registering this plugin in the shared
   `claude` CLI registry, which is machine-wide, not per-project.

2. **`--apply` without `--yes` requires an interactive `y` on stdin.**
   `` `install.sh::step()` `` reads one line and aborts on anything but `y`,
   `Y` or `yes`, and a closed stdin reads empty and aborts [verified]. Blocks:
   an unattended script or CI job that happens to call `install.sh --apply`
   from silently registering the plugin.

3. **`--apply` refuses from a linked git worktree.**
   `` `install.sh::require_main_checkout()` `` compares `git-dir` and
   `git-common-dir` and exits before any mutation when they differ
   [verified]. Blocks: the marketplace pointing at a worktree path that is
   deleted the moment its branch is removed, which would make the installed
   plugin stop loading with no clear error at that later point.

4. **The worktree guard is enforced twice, independently.** `install.sh` and
   `` `Makefile::require_main_checkout` `` both check the same condition
   [verified]. Blocks: a regression in one guard silently removing the only
   protection, since `make install` still refuses even if `install.sh`'s own
   check were ever weakened.

5. **`plugin_present()` only matches the marketplace-qualified name.**
   `` `install.sh::plugin_present()` `` greps for `${PLUGIN}@${MARKET}`, not
   the bare plugin name [verified]. Blocks: a same-named plugin registered
   under a foreign marketplace being mistaken for this one already being
   installed, which would leave this plugin's own marketplace entry unused.

6. **`check_structure()` runs independently of `claude` and of `--apply`.**
   It shells out to `python3` only and is never called from
   `` `install.sh::do_install()` `` [verified]. Blocks: a machine with no
   `claude` CLI being unable to validate the plugin tree at all; but also
   means nothing forces a structure check before an actual install (see
   [`GAPS.md`](GAPS.md)).

7. **`.mcp.json` defines exactly one server, named `outline`.**
   `` `install.sh::check_structure()` `` rejects any other server list
   [verified]. Blocks: a second MCP client being added under the plugin,
   which would make it ambiguous which `outline` connection the skill
   actually reaches when both a plugin-bundled and a user-scoped server
   exist.

8. **`.mcp.json` never holds a literal credential.** Its `headers` are
   `${CF_ACCESS_CLIENT_ID}`, `${CF_ACCESS_CLIENT_SECRET}` and
   `${OUTLINE_API_TOKEN}` placeholders only
   (`` `.mcp.json::"${OUTLINE_API_TOKEN}"` ``) [verified]. Blocks: a secret
   being committed to a file that ships inside a marketplace others may add.
