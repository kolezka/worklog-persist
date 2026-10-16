---
block: verification
doc: GAPS
verified_against: 3425d99
verified_on: 2026-10-16
---

# Gaps

What no suite in this repository proves, and where the boundary between "this
block's gap" and "another block's gap" falls. Per
`docs/CONVENTIONS.md::"Where a fact lives"`, each item below gets one sentence and
a link rather than a restatement. [verified]

---

## Nothing here proves the agent follows the skill's write protocol

The skill's rules about idempotent writes and redacting a checkpoint before it is
sent to Outline are text the agent is expected to follow, not code this repo can
execute in a test. [inferred] No suite spawns an agent session and inspects what
it actually wrote to Outline. This is `persistence-protocol`'s contract to state
and, if possible, narrow; see
[`../persistence-protocol/CONTRACTS.md`](../persistence-protocol/CONTRACTS.md) and
[`../persistence-protocol/GAPS.md`](../persistence-protocol/GAPS.md).

## Nothing here proves `additionalContext` reaches the model

`tests/test_offswitch.sh` checks that `session-start.sh` emits JSON containing the
rule text inside `hookSpecificOutput.additionalContext` when the switch is on,
and emits zero bytes when it is off. [verified] It does not run inside a real
Claude Code session, so it cannot show that the emitted context is actually read
into the model's context window rather than dropped or truncated upstream. That
question belongs to `session-hook`; see
[`../session-hook/GAPS.md`](../session-hook/GAPS.md).

## The tool-prefix check is a text match, not a runtime resolution

`tests/test_structure.sh::"skill handles both MCP tool prefixes"` only greps the
skill file for both `mcp__outline__*`-style prefixes and confirms neither is
hardcoded as a `select:` target. [verified] It does not load the plugin into a
real session and confirm which prefix the MCP tool loader actually resolves at
runtime. That resolution behaviour is `persistence-protocol`'s; see
[`../persistence-protocol/CONTRACTS.md`](../persistence-protocol/CONTRACTS.md).

## The live suite is deliberately excluded from the offline gate

`Makefile::check` runs `test`, `test-sh` and `install.sh --check` only;
`tests/test_live_outline.sh` is reachable solely through `Makefile::live` or a
direct manual invocation, and both require `OUTLINE_API_TOKEN`. [verified] This
means no CI run that only calls `make check` ever exercises a real Outline
endpoint, so a change to the endpoint URL, the auth header shape, or the Cloudflare
Access headers in `.mcp.json` can pass `make check` while being broken against the
real service. Accepted gap: credentials are never available to an unattended
offline run by design, per `docs/CONVENTIONS.md::"No world names, no credentials"`.
[verified]

## Citation checks confirm containment, not correctness

`tests/test_docs_layout.py::_citation_error()` treats a citation as valid once the
cited symbol or phrase is a literal substring of the target file. [verified] A
citation can name the right file and a real string in it while still describing
the wrong behaviour, for example if the string moved to a different function
during a refactor and the doc was not updated. This is a limit of the checker
itself, not a specific known instance in the current docs tree. [inferred]

## The regression-test rule has no automated check

`AGENTS.md::"A fix ships with a test that fails on the old code"` is enforced by
convention only; see [`CONTRACTS.md`](CONTRACTS.md) for the entry. [verified] No
suite scans commit history to confirm a given fix commit actually added a test, or
that the test was run against the pre-fix revision and observed failing. Doing so
would require re-checking out prior revisions in CI, which this repo does not do.
[inferred]
