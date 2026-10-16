---
block: verification
doc: INVARIANTS
verified_against: 7c67f29
verified_on: 2026-10-16
---

# Invariants

Numbered behaviours the test suite itself must keep. Each one names the defect it
prevents. See [`CONTRACTS.md`](CONTRACTS.md) for the entry points these suites run
under.

---

1. **The installer suite never invokes the real `claude` binary.**
   `tests/test_install.sh` puts a stub ahead of the real CLI on `PATH` before the
   first case runs, and every case restores `PATH` implicitly by exiting the
   script. [verified] Defect prevented: a test run silently registering a fake
   marketplace or plugin in the developer's real `claude` CLI registry.

2. **A `list` call is never counted as a mutation.**
   `tests/test_install.sh::mutations()` filters `marketplace list` and
   `plugin list` out of the call log before checking for unwanted mutation.
   [verified] Defect prevented: a suite that reports "read-only" success while
   masking a real accidental write, because the read-only `list` calls padded the
   log and hid the write among them.

3. **Off-switch tests run against an isolated state directory.**
   `tests/test_offswitch.sh` creates a fresh directory with `mktemp -d` and
   exports it as `XDG_STATE_HOME` before calling `persistence-state.sh` or
   `session-start.sh`. [verified] Defect prevented: a test run permanently
   flipping the off-switch in the developer's real state directory, silencing the
   hook outside the test.

4. **The resolver suite never reads the host's config or world.**
   `tests/test_context.sh` unsets the world env vars and points `WORKLOG_CONFIG`
   at a file inside its own `mktemp -d` directory before the first case.
   [verified] Defect prevented: a case passing or failing because of the
   developer's real config, which would make the suite prove nothing on a
   clean machine.

   The same suite checks that the pre-0.3 world env var and manifest have no
   effect (`tests/test_context.sh::"old coupling ignored"`), and routes made-up
   world names through the env (`tests/test_context.sh::"WORKLOG_WORLD honored"`),
   the config (`tests/test_context.sh::"config identity"`) and path root
   (`tests/test_context.sh::"path-root: deepest root wins"`). [verified] No test
   greps for real world names, since naming them would put them in a tracked
   file. [verified] Defect prevented: world routing quietly coming back from
   another tool's settings, or from a name typed into the code.

5. **Redaction is checked against ordinary text, not only against secrets.**
   `tests/test_redact.py::test_preserves_ordinary_text()` asserts a plain
   checkpoint body passes through `redact()` byte for byte. [verified] Defect
   prevented: an overly broad redaction pattern corrupting normal work notes,
   which a suite that only fed it secrets would never catch.

6. **Redaction is checked for idempotence.**
   `tests/test_redact.py::test_idempotent()` asserts that redacting an
   already-redacted string is a no-op. [verified] Defect prevented: a second write
   through the same pipeline mangling a `<REDACTED:...>` marker left by the first
   pass.

7. **The citation and link checks carry a positive control against a silently
   empty result.**
   `tests/test_docs_layout.py::"checked > 30"` and the equivalent `checked > 10`
   bound on links both fail loudly if the counting regex stops matching anything.
   [verified] Defect prevented: a future refactor of the checker (or a change to
   the citation syntax) making every doc look clean because nothing was checked at
   all, not because nothing was broken.

8. **The live suite fails safe when unconfigured.**
   `tests/test_live_outline.sh` exits `0` with a `SKIP:` message when
   `tests/test_live_outline.sh::"WORKLOG_PERSIST_LIVE"` is unset, and aborts on
   its own precondition check if `OUTLINE_API_TOKEN` is missing even when that
   flag is set. [verified] Defect prevented: a developer being tempted to hardcode
   a token in the repo, or `make check` failing in every environment that lacks
   network access, just to keep an opt-in reachability probe green.

9. **`test_docs_layout.py` checks the whole `docs/` tree, not just one block.**
   `tests/test_docs_layout.py::_docs()` globs `docs/**/*.md` from the repository
   root rather than a single block folder. [verified] Defect prevented: this
   block's own docs passing review while another block's front matter, ownership
   claim or citation is silently broken.

10. **The config-writer suite never touches the real config.**
   `tests/test_config_add.sh` exports `WORKLOG_CONFIG` inside its own
   `mktemp -d` directory before the first write, and every other case passes a
   scratch path too. [verified] Defect prevented: a test run adding fake worlds
   to the developer's real config.

11. **A refusal is checked by file content, not only by exit code.**
   `tests/test_config_add.sh::sum()` hashes the file before and after each
   refused or repeated write. [verified] Defect prevented: a writer that exits
   non-zero but has already truncated or rewritten the file, which an exit-code
   check alone would pass.
