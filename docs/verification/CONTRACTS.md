---
block: verification
doc: CONTRACTS
verified_against: fcd9e31
verified_on: 2026-10-23
---

# Contracts

Durable interfaces of the test suite itself: what each entry point runs, what a
suite promises not to touch, and how a regression fix is expected to ship. See
[`../CONVENTIONS.md`](../CONVENTIONS.md) for the `enforcement:` field rule.

---

## Entry points

### `make test` runs the Python suite only

`make test` runs `env -u FORCE_COLOR uv run pytest -q`, which collects
`tests/test_redact.py` and `tests/test_docs_layout.py`. [verified] It does not run
any `tests/*.sh` file: `Makefile::"Not collected by pytest"` is the comment
explaining why a shell suite needs a separate target. [verified]

enforcement: `Makefile::test` (target definition)

### `make test-sh` runs every shell suite

`make test-sh` loops over `tests/*.sh` and runs each with `bash`, failing the
target if any suite fails. [verified] This is the only `Makefile` target that runs
`tests/test_structure.sh`, `tests/test_install.sh`, `tests/test_context.sh`,
`tests/test_config_add.sh`, `tests/test_offswitch.sh` and
`tests/test_stop_guard.sh`. [inferred, from the glob and the absence of another
loop over `tests/*.sh` in `Makefile`]

enforcement: `Makefile::test-sh`

### `make check` is the full offline gate

`make check` runs `test`, then `test-sh`, then `install.sh --check`, and nothing
else. [verified] `Makefile::"Everything offline: both suites plus the structure check"`
is its own description of that scope. [verified] `tests/test_live_outline.sh` is
never part of `check`. [verified]

enforcement: `Makefile::check`

### `make test-native` runs the native panel suite, and refuses to skip

`Makefile::test-native` validates the plugin and runs
`tests/worklog-panel.test.tsx` with `claude plugin test`; with no `claude` on
`PATH` it prints `Makefile::"native tests did not run"` and exits non-zero
[verified: uncommitted worktree, not at the pin]. Every Outline answer in that suite is a fixture: it never reaches
a real server, a registry or a real command run (`tests/worklog-panel.test.tsx::"nothing reaches a real Outline server"`)
[verified: uncommitted worktree, not at the pin]. Each test asserts a drawn element or a recorded call, on the
terminal and desktop surfaces where it draws.

enforcement: `Makefile::test-native`; not part of `make check`.

### `make lint` shellchecks the shell surface

`make lint` runs `shellcheck` through `uvx --from shellcheck-py`, at
`Makefile::"warning severity"`, over `install.sh`, `scripts/*.sh` and
`tests/*.sh`. [verified] Shellcheck failures are lint findings, not part of `check`.
[verified]

enforcement: `Makefile::lint`

### `make live` is the only sanctioned way to run the live suite

`make live` sets `WORKLOG_PERSIST_LIVE=1` and runs `tests/test_live_outline.sh`
directly. [verified] The script itself refuses to do anything unless
`tests/test_live_outline.sh::"WORKLOG_PERSIST_LIVE"` is set to `1`, printing a
`SKIP:` line and exiting `0` otherwise. [verified] Running it through `make live`
still requires `OUTLINE_API_TOKEN` in the environment, or the script aborts on
its own precondition check before any network call. [verified]

enforcement: `Makefile::live` and `tests/test_live_outline.sh` (its own guard)

---

## Suite guarantees

### The installer test never touches the real `claude` CLI registry

`tests/test_install.sh` prepends a stub binary to `PATH` before every case. The
stub only appends its arguments to a log file named by
`tests/test_install.sh::"STUB_CALLS"` and, for a `list` subcommand, prints a
canned `STUB_LIST` value. [verified] No case in the suite calls the real `claude`
binary. [verified]

enforcement: `tests/test_install.sh` (stub definition, self-contained; no
  external check that a future edit keeps the stub on `PATH`)

### The worktree-refusal case carries a positive control

Case 6 in `tests/test_install.sh` proves `--apply` is refused from a linked
worktree via `tests/test_install.sh::"--apply refused from linked worktree"`.
[verified] Case 7 proves the same command succeeds from the main checkout of the
same repository, via `tests/test_install.sh::"--apply allowed from main checkout"`.
[verified] Without case 7, case 6 could pass because the refusal check is too
broad, rejecting every checkout, and nothing would catch it.

enforcement: `tests/test_install.sh` (both cases run in the same file, in order)

### The live suite only checks reachability

`tests/test_live_outline.sh` sends one `POST` to `auth.info` and reads the HTTP
status code; it never calls a document read or write endpoint.
`tests/test_live_outline.sh::"does NOT create or mutate documents"` states this in
its own header comment. [verified]

enforcement: `tests/test_live_outline.sh` (single `curl` call, no other network
  call in the file)

### The live suite reads the endpoint from `.mcp.json`, never a second URL

`tests/test_live_outline.sh` parses `mcpServers.outline.url` out of `.mcp.json`
at run time, via `tests/test_live_outline.sh::"mcpServers"`, instead of
hardcoding an endpoint. [verified] The full contract for that field belongs to
`persistence-protocol`; see
[`../persistence-protocol/CONTRACTS.md`](../persistence-protocol/CONTRACTS.md).

enforcement: `tests/test_live_outline.sh` (reads `.mcp.json` before building the
  request)

### `tests/test_docs_layout.py` enforces every rule marked *(tested)* in `../CONVENTIONS.md`

Front matter shape and a single pinned commit
(`tests/test_docs_layout.py::test_front_matter_is_valid_and_pinned_to_one_ancestor_commit()`),
the five-plus-one file set per block
(`tests/test_docs_layout.py::test_every_block_has_the_mandatory_file_set()`),
ownership as a partition of every tracked file
(`tests/test_docs_layout.py::test_every_tracked_file_has_exactly_one_owner()`),
citations resolving to real text
(`tests/test_docs_layout.py::test_every_symbol_citation_resolves()`), no
line-number citations
(`tests/test_docs_layout.py::test_no_line_number_citations()`), and local links
resolving (`tests/test_docs_layout.py::test_every_local_link_resolves()`) are each
one function in this file. [verified] This suite runs over the whole `docs/` tree,
not only this block, so a change in any block's docs can fail it. [verified]

enforcement: `tests/test_docs_layout.py` (all six functions above, run by
  `make test`)

### Citation and link checks carry positive controls

`tests/test_docs_layout.py::"checked > 30"` fails the citation test if fewer than
31 citations are found anywhere, which catches the regex or the whole `docs/` tree
silently disappearing instead of reporting a false "0 broken citations". [verified]
The link test carries the same shape, requiring more than 10 local links. [verified]

enforcement: `tests/test_docs_layout.py::test_every_symbol_citation_resolves()`
  and `tests/test_docs_layout.py::test_every_local_link_resolves()`

---

## Process contract

### A bug fix ships a regression test that fails on the old code

`AGENTS.md::"A fix ships with a test that fails on the old code"` states the rule
for this whole repository, not only for code under `tests/`. [verified] No suite
in this repo checks that a given commit actually followed this rule; it depends on
the author running the new test against the pre-fix code and observing a failure
before committing. See [`OPERATIONS.md`](OPERATIONS.md) for how to do that run.

enforcement: convention
