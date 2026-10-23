---
block: persistence-protocol
doc: GAPS
verified_against: fcd9e31
verified_on: 2026-10-23
---

# Gaps

Debt and unenforced boundaries in this block. Every entry here is a claim about
what does *not* check itself; the entries in [`CONTRACTS.md`](CONTRACTS.md)
carry `enforcement:` fields that say the same thing per-contract. This file
collects the pattern.

---

## The whole protocol is prompt text

`skills/worklog-persist/SKILL.md::"This skill is the operational contract"`
[verified] is a markdown file the model reads and is expected to follow; it is
not code that runs. Every rule in it, the availability check, the redact-before-
write step, the idempotent update, the verified/inferred/blocked labeling,
depends on the agent actually doing what the text says in a given session.
Nothing in this repository observes a live session and fails it for skipping a
step (`tests/test_redact.py` and `tests/test_context.sh` test the two helper
scripts in isolation, and `tests/test_structure.sh` tests that the files exist
and name the right strings; none of the three drives an actual Outline call).
Concretely, nothing stops a session from: calling `create_document` twice for
the same task slug, calling `update_document` with an unredacted secret in the
body, or reporting "saved to Outline" without ever calling a write tool. See
[`../verification/GAPS.md`](../verification/GAPS.md) for what the test suite as
a whole does and does not cover.

## No migration from the 0.2 manifest

The resolver does not look for the old manifest or read the old world env var,
by design (see [`DECISIONS.md`](DECISIONS.md#its-own-config-not-a-shared-manifest)).
An operator who upgrades gets `UNRESOLVED` for every repo, with `config_error`
set to `config not found: ...`, and the hook asks for onboarding [verified].
Nothing copies the old entries across; the schema is the same, so a manual copy
works [inferred].

## A config with one bad entry is dropped whole

`scripts/resolve_context.py::shape_error()` rejects the whole file when any one
part has the wrong shape, for example one `projects` value that is not an array
of mappings [verified]. Every repo then resolves as if no config existed. The
cause is in `config_error`, but a single typo still turns off routing for all
worlds [inferred from `load_config()` returning `None` on any shape error].

## Nothing installs PyYAML

The scripts run under whatever `python3` is on `PATH`, not the `uv` test
environment, and `pyproject.toml` lists only the test runner [verified]. A
machine without PyYAML resolves every repo as `UNRESOLVED` with
`config_error` = `config unreadable: PyYAML is not installed`, and the hook
says to fix that before onboarding [verified].

## The config writer has limits

`scripts/config_add.py::write()` rewrites the whole file, so YAML comments and
formatting are lost on the first write [verified]. Two writers at once are not
locked against each other; the last `os.replace` wins [inferred: no lock in the
code]. Nothing stops an agent from editing the YAML by hand instead of using the
script; that rule is prompt text only [verified]. Each call runs `git` three or
four times for the new repo and for every stored path that needs mapping, and
lists the parent dirs of every stored path once
(`scripts/config_add.py::dir_names()`) [verified]. With 30 stored projects a
call took about 0.13 s, against 0.07 s before the worktree mapping and 1.35 s
before the short-circuit [historical: 2026-09-28, hand-timed run with a mktemp
config].

A `project --repo` below a repo's top level is stored as that subpath (mapped to
the main checkout when typed in a worktree), and the resolver matches only the
top level, so such an entry never routes [inferred:
`scripts/resolve_context.py::find_project()` compares against `repo_root`, and
`scripts/config_add.py::main_checkout()` keeps the subpath].

A symlink loop at the config path is not detected. `os.path.realpath` stops
inside the loop, the missing file reads as empty, and one link of the loop is
replaced by a regular file that holds only the new entry [verified: run by hand
on 2026-09-28 with a two-link loop]. The version before the write-through fix
replaced the configured link the same way [inferred: it called `os.replace` on
the configured path].

Both the writer and the resolver honour `GIT_DIR` from the environment through
`scripts/resolve_context.py::canonical_repo()`. With `GIT_DIR` set to a linked
worktree's git dir, `ignore --repo` on an unrelated repo stored the other repo's
main checkout, and the resolver run from the unrelated repo reported that main
checkout as `repo_root` [verified: run by hand on 2026-09-28]. Not fixed. Nothing in
the plugin sets it [verified: no `GIT_DIR` in `hooks/`, `scripts/`, `skills/` or
`commands/`], but an inherited environment can.

## Onboarding is prompt text

The discovery, the question and the bootstrap in
`skills/worklog-persist/SKILL.md::"## Onboarding (unresolved repo)"` are not
run by any test [verified]. A session could skip the question or treat a
non-world top-level document under `root_collection` as a world [inferred]. A
worktree path passed instead of `repo_root` is harmless, because the writer maps
it to the main checkout (`tests/test_config_add.sh::"worktree: resolves from main"`)
[verified].

## Redaction coverage is a fixed rule list, not a guarantee

`scripts/redact.py::"defence-in-depth filter"` [verified] and
`scripts/redact.py::"do not put secrets into the record in the first place"`
[verified] both say this directly in the module's own docstring: `_RULES` is a
finite, hand-maintained list of shapes (bearer tokens, a handful of vendor key
prefixes, PEM blocks, generic `key=value`, URL passwords, IBAN, Polish NIP). A
secret in a shape not on that list passes through unredacted, and the write-
before-redact ordering in every command depends entirely on the agent
remembering to run it, per the "whole protocol is prompt text" gap above.

## Commands do not repeat the ToolSearch discovery step

None of the eight `commands/*.md` files mentions `ToolSearch` or the dual-
prefix rule; they call the tool verbs directly (`list_collections`,
`create_document`, and so on) and rely on the invoking session having already
loaded `skills/worklog-persist/SKILL.md::"Find them with ToolSearch"` [verified]
by that point. This is consistent with the design in
[`DECISIONS.md`](DECISIONS.md) (one canonical file, thin command pointers), but
it means a command run without the skill's tool-discovery text loaded first has
no fallback instruction of its own for finding the right prefix
[inferred: no code path in this repo forces the skill body to load before a
command body does].

## No test exercises the idempotency contract end to end

`tests/test_context.sh` and `tests/test_redact.py` cover
`scripts/resolve-context.sh` and `scripts/redact.py` in isolation, and
`tests/test_structure.sh::"all 8 verb commands present"` [verified] only checks
file existence. None of them, nor anything else found at this pin, drives a
`list_documents` / `create_document` / `update_document` sequence to prove the
"match on project + task slug, update instead of duplicate" rule actually holds
against a real or mocked Outline. `tests/test_live_outline.sh` exists and is
closest to this, but it is owned by [`verification`](../verification/README.md);
see that block's docs for what it actually proves.

## The pinned protocol rules from 0.3.2's follow-up are not described here yet

The pin moved to the commit that merged three skill rules: compacting a record
over about 4,000 characters into a `history before compaction` child
(`skills/worklog-persist/SKILL.md::"history before compaction"`), the fixed
`Tasks` flag line format (`skills/worklog-persist/SKILL.md::"(<flag>, <YYYY-MM-DD>)"`),
and never creating a root collection that only the default names
(`scripts/resolve_context.py::"root_source"`) [verified]. The skill and
`tests/test_structure.sh::"a default-only root collection is asked about, not created"`
carry them [verified]; this block's CONTRACTS and INVARIANTS do not restate them
yet.
