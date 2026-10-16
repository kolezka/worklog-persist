---
block: persistence-protocol
doc: CONTRACTS
verified_against: 7d87d3b
verified_on: 2026-10-16
---

# Contracts

Durable interfaces of the skill, the commands and the two helper scripts. See
[`../CONVENTIONS.md`](../CONVENTIONS.md) for the citation and `enforcement:`
format.

---

## The skill is the single operational contract

`skills/worklog-persist/SKILL.md::"This skill is the operational contract"`
[verified]. The eight command files exist and each names its verb: `load`,
`start`, `checkpoint`, `handoff`, `complete`, `dry-run`, `off`, `setup`
[verified]. Each command body says "Run the worklog-persist skill's" plus its own
step, for instance `commands/handoff.md::"Run the worklog-persist skill's"`
[verified], rather than restating the lifecycle rules, so a rule only needs to
change in `skills/worklog-persist/SKILL.md` once [inferred: one canonical file,
eight short pointers].

enforcement: `tests/test_structure.sh::"all 8 verb commands present"` checks
only that the eight files exist, not that their bodies still defer to the
skill (test suite only).

---

## MCP tool discovery: two possible prefixes, never assumed

The Outline tools are `list_collections`, `list_documents`, `fetch`,
`create_document`, `update_document`, `move_document`
(`skills/worklog-persist/SKILL.md::"Their prefix depends on"`)
[verified]. Their prefix is `mcp__outline__*` when a user, project or local scope
also configures an `outline` server, or
`mcp__plugin_worklog-persist_outline__*` when only the plugin's own server
definition exists, because Claude Code connects once per matching server
definition rather than exposing both
(`skills/worklog-persist/SKILL.md::"Claude Code then connects once"`)
[verified]. Which case applies depends on `.mcp.json`, owned by
[`packaging`](../packaging/CONTRACTS.md); this block only names both outcomes and
never assumes one, one sentence and a link per
[`../CONVENTIONS.md`](../CONVENTIONS.md) [inferred]. The skill instructs
discovery by keyword, not by hardcoding either string:
`skills/worklog-persist/SKILL.md::"Find them with ToolSearch"` and
`skills/worklog-persist/SKILL.md::"Never assume"` [verified]. None of
the eight `commands/*.md` files contains the literal string `mcp__`, so they
cannot hardcode the wrong one; they name only the tool verbs and defer prefix
discovery to the skill [verified].

Background on why Claude Code exposes only one prefix per logical server:
[Claude Code MCP docs](https://code.claude.com/docs/en/mcp) [assumption: external
source, not re-verified against the running product for this pin].

enforcement: `tests/test_structure.sh::"skill handles both MCP tool prefixes"`
asserts the skill text names the plugin-scoped prefix and does not hardcode a
`select:mcp__outline__` filter (test suite only; nothing checks this at agent
run time).

---

## Identity resolution: `scripts/resolve-context.sh`

Invoked as `skills/worklog-persist/SKILL.md::"bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-context.sh"`
[verified]. The shell file is a thin wrapper that execs
`scripts/resolve_context.py` (`scripts/resolve-context.sh::"Thin wrapper"`)
[verified]. `scripts/resolve_context.py::main()` prints one JSON object with
these keys: `repo`, `repo_root`, `project`, `world`, `world_source`,
`candidate_worlds`, `ignored`, `branch`, `worktree`, `task_slug`,
`root_collection`, `global_collection`, `archive_collection`, `kb_path`,
`tasks_path`, `record_path`, `config`, `config_path`, `config_error` [verified].

- `repo_root` is the main checkout, also from a linked worktree
  (`scripts/resolve_context.py::canonical_repo()`) [verified].
- `project` is the config `name` of a declared repo, else the basename of the
  `origin` remote with `.git` stripped, else the main checkout directory name
  (`scripts/resolve_context.py::"remote", "get-url", "origin"`) [verified].
  Outside any git repo it is `workspace`
  (`scripts/resolve_context.py::"workspace"`) [verified].
- `world` has four tiers [verified]:
  1. the repo is declared in the config (`world_source` = `config`);
  2. `$WORKLOG_WORLD` (`env`, `scripts/resolve_context.py::"WORKLOG_WORLD"`);
  3. path root (`path-root`): the config world whose declared repos' common
     ancestor is the deepest ancestor-or-equal of this repo; a tie between two
     different worlds at that depth gives nothing
     (`scripts/resolve_context.py::path_root_world()`);
  4. the sentinel `UNRESOLVED` (`fallback`).

  An ignored repo takes no world from tiers 2 or 3 [verified]. No other env var
  or file sets it: only the one config is read [verified].
- `candidate_worlds` lists the world names declared in the config [verified].
- `kb_path` is the config `kb_folder` when set, else
  `<root_collection>/<world>/<project>`, and `None` while the world is
  `UNRESOLVED` [verified]. `tasks_path` and `record_path` hang off it.
- `config` is the path that was read, or `None`; `config_path` is where the
  config is looked for, also when it does not exist; `config_error` says why no
  config was used (`not found`, `unreadable`, `malformed`), or is `None`
  (`scripts/resolve_context.py::load_config()`) [verified].
- `task_slug`, when given, must match `scripts/resolve_context.py::SLUG_RE`
  (kebab-case, optionally ticket-prefixed like `AD-163-uat-checklist`), or the
  script exits `2` with a message on stderr
  (`scripts/resolve_context.py::"invalid task slug"`) [verified].

enforcement: `tests/test_context.sh::"WORKLOG_WORLD honored"`,
`tests/test_context.sh::"config identity"`,
`tests/test_context.sh::"worktree identity"`,
`tests/test_context.sh::"ignored beats WORKLOG_WORLD"`,
`tests/test_context.sh::"path-root: deepest root wins"`,
`tests/test_context.sh::"equal-depth tie is ambiguous"`,
`tests/test_context.sh::"ignored beats path-root"`,
`tests/test_context.sh::"non-git project workspace"`,
`tests/test_context.sh::"old coupling ignored"` and
`tests/test_context.sh::"invalid slug rejected"` (test suite only, via
`make check`, not on every invocation of the script).

---

## Plugin config file

The resolver reads one YAML file: `$WORKLOG_CONFIG`, else
`~/.config/worklog-persist/config.yaml`
(`scripts/resolve_context.py::config_path()`) [verified]. It is parsed with
PyYAML's `safe_load`; without PyYAML the resolver reports
`scripts/resolve_context.py::"PyYAML is not installed"` in `config_error` and
does not crash [verified]. The shape it reads:

- `outline:` with `root_collection`, `global_collection`, `archive_collection`.
  A missing key keeps `scripts/resolve_context.py::DEFAULT_OUTLINE` [verified],
  a neutral placeholder (`"Worklog"`, `"Claude's Notebook"`, `"Archive"`), never
  one operator's real collection name [verified]. An operator who wants their
  own naming sets `outline.root_collection` (and the other two keys, if wanted)
  in their config; see [`README.md`](../../README.md#install) for the exact
  block to add.
- `worlds:`, a list of `{name, projects}`, where `projects` is a list of
  `{name, repo, kb_folder?}`. `repo` is matched after `~` expansion and symlink
  resolution (`scripts/resolve_context.py::expand()`) [verified].
- `ignore:`, a list of dirs: a repo equal to or below one of them is `ignored`
  [verified].

Any other key is ignored. A file with the wrong shape is rejected whole by
`scripts/resolve_context.py::shape_error()` and reported in `config_error`, never
raised [verified].

enforcement: `tests/test_context.sh::"malformed config"`,
`tests/test_context.sh::"unparseable config"`,
`tests/test_context.sh::"missing config reported"`,
`tests/test_context.sh::"default config path"` and
`tests/test_context.sh::"no PyYAML"` (test suite only).

---

## Config writer: `scripts/config-add.sh`

The only sanctioned writer of the config. A thin wrapper
(`scripts/config-add.sh::"Thin wrapper"`) around `scripts/config_add.py::main()`,
which writes the same file the resolver reads (it imports
`scripts/resolve_context.py::config_path()`) [verified]. Two subcommands:

- `project --world W --name N --repo PATH [--kb-folder F]` declares a repo
  (`scripts/config_add.py::add_project()`) [verified];
- `ignore --repo PATH` marks a repo as having no Outline folder
  (`scripts/config_add.py::add_ignore()`) [verified].

Behaviour [verified, from the code and `tests/test_config_add.sh`]:

- A missing file and its parent dirs are created. Existing entries and keys are
  kept; YAML comments are not.
- `repo` is stored as the resolved absolute path. A path in a linked git
  worktree is stored as the same path in the main checkout
  (`scripts/config_add.py::main_checkout()`, reusing
  `scripts/resolve_context.py::canonical_repo()`), which is what the resolver
  matches. A declare from the worktree and one from the main checkout are the
  same entry. The top level is found with `os.path.samefile`, so on a
  case-insensitive disk a path typed in another case has its git top level
  stored in the on-disk case; a subpath below the top level keeps the case it
  was typed in. A path that cannot be related to its top level is refused with exit `2`. With
  no `git` binary the path is stored as given.
- Stored repo paths (projects and `ignore`) are compared through the same
  mapping (`scripts/config_add.py::canonical()`), so an entry an older version
  stored under a worktree path, or in another case, still counts as that repo.
  Git runs only for a stored path inside a linked worktree or spelled in
  another case than the disk holds (`scripts/config_add.py::needs_mapping()`);
  any other path already is its main checkout.
- The same entry again is a no-op: exit `0`, `no change` on stdout, file
  untouched. The exception: when the stored spelling differs from the
  canonical path (a worktree path, or another case on a case-insensitive
  disk), the entry is rewritten to the canonical path, because the resolver
  never matches the old spelling. If an entry with the canonical path already
  exists, the other spellings are dropped instead, so no entry is duplicated.
  The same holds for `ignore` entries.
- A repo already declared differently (another world, name or `kb_folder`), a
  declared repo passed to `ignore`, or an ignored repo passed to `project`:
  exit `1`, nothing written.
- A file that does not parse or fails `scripts/resolve_context.py::shape_error()`:
  exit `1`, file left byte-identical.
- No PyYAML: exit `1`, nothing written.
- A world or project name that is empty or holds `/`, a `--repo` that is not
  a directory, or a worktree subdir that does not exist in the main checkout:
  exit `2`, nothing written.
- Writes go to a temp file in the same dir, then `os.replace`
  (`scripts/config_add.py::write()`). A symlinked config, or a chain of
  symlinks, is written through: the temp file and the replace happen next to
  the real target, so the link stays a link and the target's mode is kept. A
  symlink loop is not detected; see [GAPS](GAPS.md).

enforcement: `tests/test_config_add.sh` (every bullet above, test suite only,
except `fsync`, the symlink chain and the refusal of a path that cannot be
related to its top level, which no test covers; the case-insensitive case runs
only on a case-insensitive disk). The rule that an agent uses this script and
never edits the YAML by hand is prompt text only
(`skills/worklog-persist/SKILL.md::"never by editing the YAML"`): convention.

---

## Onboarding an unresolved repo

When the resolver gives `UNRESOLVED` (so not a `path-root` match), not `ignored`, and `config_error` is empty
or `config not found`, the skill runs its onboarding flow
(`skills/worklog-persist/SKILL.md::"## Onboarding (unresolved repo)"`)
[verified]. `/setup` runs the same flow (`commands/setup.md::"Onboarding"`)
[verified]. The flow: list the top-level documents under `root_collection` as
the worlds, never hardcoded or cached; ask one question (a world, a new world,
or do not persist, plus the project name); record the answer with
`config-add.sh`; bootstrap a new world with `INDEX` only and then the project
folder; re-run the resolver and confirm `kb_path` [verified]. Without Outline it
offers only a typed world or "Skip for this session" and writes nothing to
Outline [verified].

enforcement: convention. The flow is prompt text; no test drives it. The hook
side that asks for it is tested in
[`../session-hook/CONTRACTS.md`](../session-hook/CONTRACTS.md), and the writer
in `tests/test_config_add.sh`.

---

## Secret redaction: `scripts/redact.py`

A stdin-or-file-args-to-stdout filter: `redact(text: str) -> str` applies an
ordered list of regex rules and returns the rewritten text
(`scripts/redact.py::redact()`) [verified]. Rules live in
`scripts/redact.py::_RULES` and run in order so a specific pattern (a GitHub
token, an IBAN) wins over the generic `key=value` catch-all
(`scripts/redact.py::"structured/longer"`) [verified]. Every match becomes
`<REDACTED:kind>`, for example `<REDACTED:api-key>`, `<REDACTED:private-key>`,
`<REDACTED:nip>` (`scripts/redact.py::"<REDACTED:kind>"`) [verified]. `main()`
reads args-as-files or stdin and writes to stdout
(`scripts/redact.py::main()`) [verified].

The skill requires every candidate record body to pass through this filter
before any write:
`skills/worklog-persist/SKILL.md::"Pipe every candidate record body through"`
[verified]. All five write-capable commands repeat the instruction, for example
`commands/start.md::"Pipe the body through"` [verified] and
`commands/checkpoint.md::"Redact via"` [verified].

enforcement: `tests/test_redact.py::test_generic_named_secret()`,
`tests/test_redact.py::test_private_key_block()` and
`tests/test_redact.py::test_url_password()` exercise `redact()` in isolation
(unit test, in the test suite only). Nothing enforces that an agent session
actually pipes a given write through `redact.py` before calling
`create_document` or `update_document`; that step is prompt text only, see
[`GAPS.md`](GAPS.md).

---

## Persisted record identity: idempotency key

The record's identity is `project` + `task_slug`, realized as the document at
`record_path`
(`skills/worklog-persist/SKILL.md::"The record identity is"`) [verified]. Before
creating a record, the commands call `list_documents` scoped to that `Tasks`
folder and match the slug; if found, they `update_document` it instead
(`commands/start.md::"prefer updating the existing record over creating a duplicate"`)
[verified]. `commands/checkpoint.md::"idempotency key = project + task slug"`
names the same rule for the checkpoint step [verified]. A timestamp alone is explicitly
rejected as an identity source:
`skills/worklog-persist/SKILL.md::"Never use a timestamp as document identity."`
[verified].

enforcement: convention. No test drives a real or mocked `list_documents` /
`create_document` round trip against this rule; `tests/test_redact.py` and
`tests/test_context.sh` cover the two helper scripts, not the Outline calls
the skill text describes. See [`../verification/README.md`](../verification/README.md)
for what the test suite as a whole proves.

---

## Availability precondition

Every command opens with an availability check before any read or write:
`skills/worklog-persist/SKILL.md::"confirm the server is connected"` [verified],
and each command file repeats it, e.g.
`commands/load.md::"MCP server is available"` [verified]. On failure, the rule is
to say so once and continue the task without Outline, never to substitute a
local claim of success:
`skills/worklog-persist/SKILL.md::"state once that persistence is"` [verified].
There is no offline read path: `/load` says persistence is unavailable and stops
(`commands/load.md::"say persistence is unavailable and stop"`) [verified].

enforcement: convention. This is prompt text interpreted by the model each
session; no script or test observes whether the agent actually checked
availability before writing.
