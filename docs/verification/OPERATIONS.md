---
block: verification
doc: OPERATIONS
verified_against: 2d0b8af
verified_on: 2026-10-18
---

# Operations

How to run each suite, what each command needs installed, how to run the one live
suite without leaking a credential, and how to red-run a regression test before
trusting it. See [`CONTRACTS.md`](CONTRACTS.md) for what each target promises.

---

## Required tools

- `bash`, for the six offline shell suites and the `test-sh` loop. [verified]
- `git`, because `tests/test_install.sh` case 6 and 7 create a throwaway repo and
  a linked worktree with `git init`, `git worktree add` and `git commit`.
  [verified]
- `python3`, used directly by every shell suite for JSON parsing (for example
  `tests/test_context.sh::field()`) and by `install.sh --check`. [verified]
- PyYAML for that same `python3`: the resolver and config-writer suites read
  and write YAML configs, and `tests/test_config_add.sh` imports `yaml` itself.
  [verified]
- `uv`, to run the `pytest` suite; `AGENTS.md::"is the only correct pytest call"`
  names `env -u FORCE_COLOR uv run pytest -q` as the one correct invocation.
  [verified]
- `uvx` with the `shellcheck-py` package, for `make lint`; no local `shellcheck`
  install is required. [verified]
- `curl`, only for `tests/test_live_outline.sh`. [verified]

---

## Running the offline suites

| Command | Runs |
|---|---|
| `make test` | `tests/test_redact.py`, `tests/test_docs_layout.py` |
| `make test-sh` | `tests/test_structure.sh`, `tests/test_install.sh`, `tests/test_context.sh`, `tests/test_config_add.sh`, `tests/test_offswitch.sh`, `tests/test_stop_guard.sh` |
| `make lint` | `shellcheck` on `install.sh`, `scripts/*.sh`, `tests/*.sh` |
| `make check` | `test`, then `test-sh`, then `install.sh --check` |

A single suite can be run directly, without `make`:

```
bash tests/test_structure.sh
bash tests/test_install.sh
bash tests/test_context.sh
bash tests/test_config_add.sh
bash tests/test_offswitch.sh
bash tests/test_stop_guard.sh
uv run pytest -q tests/test_redact.py
uv run pytest -q tests/test_docs_layout.py
```

A single test function inside the Python suites takes `pytest -k`, for example
`uv run pytest -q tests/test_redact.py -k test_idempotent`. [inferred, standard
`pytest` behaviour]

---

## Running the live suite safely

`tests/test_live_outline.sh` is opt-in and makes one real network call. Do not add
it to any script that runs unattended or in CI. [inferred, from its exclusion in
`Makefile::check`]

1. Set `OUTLINE_API_TOKEN` in your own shell environment, never in a tracked file.
   Per `docs/CONVENTIONS.md::"No world names, no credentials"`, no committed file
   may hold the value. [verified]
2. Run `make live`, which sets
   `tests/test_live_outline.sh::"WORKLOG_PERSIST_LIVE"` for you and invokes the
   script. [verified]
3. The script reads the endpoint from `.mcp.json` itself
   (`tests/test_live_outline.sh::"mcpServers"`); do not pass a second URL. [verified]
4. If your Outline instance sits behind Cloudflare Access, also export
   `CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET`; the script only adds those
   headers when the variables are set. [verified]
5. A `PASS` line reports HTTP 200 from `auth.info`. Any other code, including 000
   for a connection failure, is a `FAIL` and a nonzero exit. [verified]

This check only proves the endpoint is reachable and the token authenticates. It
does not read or write a document; see
[`GAPS.md`](GAPS.md#the-live-suite-is-deliberately-excluded-from-the-offline-gate).

---

## Doing a red run of a regression test

`AGENTS.md::"A fix ships with a test that fails on the old code"` means a new test
is worthless as a regression guard until you have watched it fail. Steps:

1. Write the test against the current, buggy behaviour and confirm it fails for
   the right reason (not a typo or a missing fixture).
2. For a Python case: `uv run pytest -q tests/<file>.py -k <test_name>` and read
   the failure. For a shell case: `bash tests/<file>.sh` and read which `check` or
   `fail` line fired.
3. Apply the fix.
4. Re-run the same command and confirm it now passes.
5. Run the full suite it belongs to (`make test` or `make test-sh`) once more, to
   catch a fix that broke a neighbouring case.

To see the test fail again on demand later, without touching the fix, check out
the pre-fix revision of only the changed file into a scratch copy (for example
`git show <commit>^:<path> > /tmp/old` and diff against the current file) rather
than reverting the fix in place; reverting in place and forgetting to restore it
is a self-inflicted regression.
