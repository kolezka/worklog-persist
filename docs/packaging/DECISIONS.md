---
block: packaging
doc: DECISIONS
verified_against: b92a027
verified_on: 2026-10-23
---

# Decisions

Why this block is shaped as it is, backed by a choice recorded in the code or
the top-level docs, not by guesswork.

## Dry-run by default

`install.sh`'s header comment states the policy directly:
`` `install.sh::"Dry-run by default"` `` [verified]. `install.sh::step()`
enforces it: without `--apply` every mutating call is printed as a `PLAN:`
line and never executed [verified]. The alternative, mutating on a bare
invocation, is what most installers do; this one does not, because the thing
it mutates is the `claude` CLI's own registry, which is shared across every
project on the machine, not scoped to this repo. A mistaken `./install.sh` in
the wrong directory costs nothing under this policy [inferred from the
comment plus the scope of what `do_install()` touches].

## Refusing `--apply` from a linked worktree

`` `install.sh::require_main_checkout()` `` and its comment give the reason
directly: `claude plugin marketplace add` records `$ROOT` as a path, and a
worktree's path is deleted with its branch
(`` `install.sh::"records $ROOT"` ``) [verified]. The alternative was
to let `--apply` run anywhere and leave the resulting dangling registration
for someone to debug later, once the branch was gone and the plugin quietly
stopped loading. Checking two things that are cheap to compute
(`git rev-parse --git-dir` and `--git-common-dir`) up front was chosen over
that failure mode, and the same check was duplicated in `Makefile` rather than
trusted to only exist in one place [verified].

## Named `worklog-persist`, not `outline-persist`

The top-level `README.md` states the reason directly:
`` `README.md::"a plugin with the same name shadows them"` `` [verified],
referring to the separate Outline MCP server and the KB skill also named
`outline`. The rename table in the same file
(`` `README.md::"Renamed from"` ``) records what moved: the plugin and skill
name, the marketplace name, two environment variables, and the state
directory [verified]. The alternative, keeping `outline-persist`, was rejected
because a plugin claiming that name would shadow the pre-existing `outline`
server and skill identity in tool and command discovery, which this plugin
does not own and must not collide with.

## `uv` plus a non-package `pyproject.toml`

`pyproject.toml` exists only to pin a test runner, not to define an
installable package: `` `pyproject.toml::"Not a Python package"` `` and
`` `pyproject.toml::"package = false"` `` under `[tool.uv]` [verified]. The
alternative, a `requirements.txt` with a manually maintained pin, was passed
over for a lockfile-backed resolver (`uv.lock`) so `env -u FORCE_COLOR uv run
pytest -q` (`` `Makefile::"Python suite"` ``) resolves the same dependency
versions on every machine without a virtualenv-activation step, while still
never asking `pip`/`build` to package a plugin that is not a library
[inferred from the comment and the `dev` dependency group holding only
`pytest`].
