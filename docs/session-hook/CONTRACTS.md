---
block: session-hook
doc: CONTRACTS
verified_against: b92a027
verified_on: 2026-10-23
---

# Contracts

Durable interfaces owned by this block. See [`../CONVENTIONS.md`](../CONVENTIONS.md)
for the `enforcement:` field format.

## `hooks/hooks.json` shape

### The manifest wraps each event in `{"hooks": {"<Event>": [...]}}`

Claude Code's plugin loader expects a top-level `hooks` object keyed by event
name, each value a list of `{matcher, hooks: [...]}` entries `[verified]`. The
file has exactly one `SessionStart` entry and one `Stop` entry, each with
`matcher: "*"` and one command hook (`hooks/hooks.json::"matcher"`,
`hooks/hooks.json::"stop-guard.sh"`) `[verified]`.

enforcement: `tests/test_structure.sh::"hooks.json missing wrapped SessionStart"`
  and `tests/test_structure.sh::"hooks.json missing wrapped Stop"` (test suite);
  `install.sh::check_structure()` checks only `SessionStart`, at `--check` time
  `[verified]`.

### The command line uses `${CLAUDE_PLUGIN_ROOT}`, never a literal path

`hooks/hooks.json::"${CLAUDE_PLUGIN_ROOT}"` resolves the plugin's own install
directory at run time, supplied by the Claude Code plugin loader, so the same
manifest works regardless of where the plugin was installed `[verified]`. Both
command strings wrap the expanded path in double quotes
(`hooks/hooks.json::"\"${CLAUDE_PLUGIN_ROOT}"`) so a path containing a space
cannot split the command into several words `[verified]`.

enforcement: `claude plugin validate --strict .` flags an unquoted
  `${CLAUDE_PLUGIN_ROOT}` as a warning, which `--strict` turns into a failing
  exit code `[verified: ran at this pin]`. No test in this repo's own suite
  inspects the literal `command` string; `tests/test_structure.sh` only checks
  that the `SessionStart` key exists, not that the manifest invokes it
  correctly `[verified]`.

## `scripts/session-start.sh` output contract

### Emits `hookSpecificOutput.additionalContext` JSON, or nothing

When persistence is on, the script prints one JSON object to stdout with keys
`hookSpecificOutput.hookEventName` set to `"SessionStart"` and
`hookSpecificOutput.additionalContext` set to the reminder string
(`scripts/session-start.sh::"hookSpecificOutput"`,
`scripts/session-start.sh::"hookEventName"`,
`scripts/session-start.sh::"additionalContext"`) `[verified]`. When off, it exits
`0` before printing anything `[verified]`.

enforcement: `tests/test_offswitch.sh::"hook emits when on"` parses the output
  as JSON and indexes both keys, and
  `tests/test_offswitch.sh::"hook silent when off"` asserts the byte count is
  `0`. Both are run-time checks in the offline test suite, not at hook-install
  time.

### The JSON is built with `json.dumps`, never hand-assembled

The reminder text is passed to a `python3` heredoc that calls
`scripts/session-start.sh::"json.dumps"` on a dict, instead of interpolating the
text into a JSON string literal in bash `[verified]`. This keeps embedded quotes
and backticks in the reminder text from producing invalid JSON `[inferred]`.

enforcement: convention. No test feeds the script a reminder string containing
  a double quote or backslash to confirm the escaping holds; the current
  reminder text just happens not to need it `[verified]`.

### The reminder carries the resolved identity, or the reason it has none

After the static rule, the script runs `resolve-context.sh` and appends one
sentence `[verified]`:

- with a `kb_path`: the world, project, KB folder and tasks path
  (`scripts/session-start.sh::"Resolved for this repo"`);
- for an ignored repo: that it has no Outline folder
  (`scripts/session-start.sh::"in the worklog-persist config"`);
- otherwise: that the world is unresolved, with the resolver's `config_error`
  as the cause (or a default cause naming `WORKLOG_WORLD`) and its
  `config_path` (`scripts/session-start.sh::"config_error"`). Then one of two
  instructions:
  - config missing, or repo not declared: run the onboarding flow before any
    other work (`scripts/session-start.sh::"run the onboarding flow"`), which the
    skill owns (see
    [`../persistence-protocol/CONTRACTS.md`](../persistence-protocol/CONTRACTS.md#onboarding-an-unresolved-repo));
  - config present but unreadable or malformed: fix it first and do not run
    `/setup` (`scripts/session-start.sh::"Fix the config file"`).

The base reminder text before this sentence is fixed; only the appended
sentence varies `[verified]`.

A resolver failure adds nothing and never fails the hook
(`scripts/session-start.sh::"a resolver failure must never break session start"`)
`[verified]`.

enforcement: `tests/test_offswitch.sh::"hook names kb_path"`,
  `tests/test_offswitch.sh::"hook states unresolved cause"`,
  `tests/test_offswitch.sh::"onboarding when config missing"`,
  `tests/test_offswitch.sh::"onboarding when repo not declared"`,
  `tests/test_offswitch.sh::"no onboarding when resolved"`,
  `tests/test_offswitch.sh::"no onboarding when ignored"`,
  `tests/test_offswitch.sh::"no onboarding when config broken"` and
  `tests/test_offswitch.sh::"base rule kept when onboarding"` (test suite only).

### The hook names the server, not a tool prefix

The reminder text refers to `` `outline` `` as an MCP server name
(`scripts/session-start.sh::"durable work-state store"`), but never spells out a
`mcp__...` tool prefix `[verified]`. Resolving the live prefix
(`mcp__outline__*` or the plugin-scoped one) is left entirely to the skill in
`persistence-protocol`, one sentence and a link per
[`../CONVENTIONS.md`](../CONVENTIONS.md): see
[`../persistence-protocol/CONTRACTS.md`](../persistence-protocol/CONTRACTS.md).

enforcement: convention. Nothing in this block checks that the reminder text
  stays prefix-agnostic; a future edit could hardcode a prefix without failing
  any test owned by this block `[verified]`.

## `scripts/persistence-state.sh` interface

### Four subcommands: `path`, `status`, `off`, `on`

`scripts/persistence-state.sh::"usage: persistence-state.sh {path|status|off|on}"`
is both the usage message and the full set of valid first arguments, dispatched
by a `case` statement; any other argument exits `2` `[verified]`.

enforcement: `tests/test_offswitch.sh` exercises `status`, `off`, and `on`
  at run time. `path` is not called by any test in this repo `[verified]`;
  see [`GAPS.md`](GAPS.md).

### `status` prints exactly `on` or `off`

`scripts/persistence-state.sh::is_off()` decides; `status` echoes `off` when it
returns true, `on` otherwise `[verified]`.

enforcement: `tests/test_offswitch.sh::"default on"` and the paired
  `off`/`on` toggle checks assert the literal string.

### State path resolution: ask the resolver, never restate it

`scripts/persistence-state.sh::state_dir()` resolves `XDG_STATE_HOME`, falling
back to `$HOME/.local/state`, and appends the literal directory name
`worklog-persist` `[verified]`. `scripts/persistence-state.sh::state_file()`
appends `/off` to that directory `[verified]`. Any other document that needs the
state path cites these two functions and their precedence, never a literal path
`[verified]`, per [`../CONVENTIONS.md`](../CONVENTIONS.md).

enforcement: `tests/test_offswitch.sh` sets `XDG_STATE_HOME` to an isolated
  temp directory for the whole suite, which only works if `state_dir()` actually
  honors that variable `[verified]`.

### `WORKLOG_HOOK_OFF=1` overrides the marker file, in both directions

`scripts/persistence-state.sh::is_off()` checks
`scripts/persistence-state.sh::"WORKLOG_HOOK_OFF"` before it checks the marker
file, so the env var forces `off` even with no marker file present, and the `on`
command cannot clear it `[verified]`. The `on` command detects this and prints a
warning rather than claiming success
(`scripts/persistence-state.sh::"off-file cleared"`) `[verified]`.

enforcement: `tests/test_offswitch.sh::"env override status"` and
  `tests/test_offswitch.sh::"env override silences hook"`, run-time checks in
  the offline suite.

## `scripts/stop-guard.sh` output contract

### Prints `{"decision":"block","reason":...}` or nothing, always exit `0`

Input is the Stop-hook JSON on stdin (`session_id`, `transcript_path`, `cwd`,
`stop_hook_active`). Output is one block decision or no bytes. Any internal
error allows the stop (`scripts/stop_guard.py::main()`, and the wrapper's
`scripts/stop-guard.sh::"exit 0"`) `[verified]`.

enforcement: `tests/test_stop_guard.sh` (test suite only).

### When it blocks

It blocks only when the non-sidechain tool calls after the later of the last
Outline write and the session marker include a `Bash` command that ships work:
`git commit`/`push`, `gh pr create`/`merge`, `gh release create`, a package
publish, or a deploy (`scripts/stop_guard.py::SHIP_RE`,
`scripts/stop_guard.py::has_shipped()`) `[verified]`. Edits and long runs of
tool calls never block on their own, however many there are `[verified]`.

It never blocks when `stop_hook_active` is set, when the session is unattended,
when persistence is off, for an ignored repo, inside the cooldown, or when it
cannot record the block (`scripts/stop_guard.py::run()`) `[verified]`:

- **Unattended.** `scripts/stop_guard.py::is_unattended()` reads
  `CLAUDE_CODE_SESSION_ATTENDED` (`0` or `1`) from the hook's environment. When
  that is unset it falls back to `CLAUDE_CODE_ENTRYPOINT`, and treats the values
  in `scripts/stop_guard.py::UNATTENDED_ENTRYPOINTS` as unattended. With neither
  set it assumes a human is present `[verified]`. Claude Code sets both
  variables, and the Stop-hook stdin carries no equivalent field
  `[historical: 2026-10-01, scratch-config Stop-hook probe on Claude Code 2.1.286]`;
  see [`GAPS.md`](GAPS.md#the-attended-signal-rests-on-probed-claude-code-variables).
- **Cooldown.** No block within `WORKLOG_STOP_COOLDOWN_MIN` minutes (default
  `scripts/stop_guard.py::DEFAULT_COOLDOWN_MIN`) of this session's last block or
  last Outline write, whichever is later. The last block is the session marker's
  mtime (`scripts/stop_guard.py::last_block_time()`). The last write is the
  `timestamp` of the transcript record that holds it
  (`scripts/stop_guard.py::parse_timestamp()`) `[verified]`. `0` turns the
  cooldown off `[inferred]` from the strict `<` comparison in
  `scripts/stop_guard.py::run()`. A time later than the local clock is ignored
  `[verified]`. A stop skipped by the cooldown leaves the marker where it was,
  so that work still counts at the first stop after the cooldown `[verified]`.
- **Unrecordable.** `scripts/stop_guard.py::write_marker()` returns false when
  there is no `session_id`, the last tool_use has no id, or the state dir cannot
  be written, and the hook then allows the stop `[verified]`. A block it could
  not record would repeat on every later stop `[inferred]` from
  `scripts/stop_guard.py::marker_index()` finding nothing.

A non-integer `WORKLOG_STOP_COOLDOWN_MIN` falls back to its default
(`scripts/stop_guard.py::env_int()`) `[verified]`.

enforcement: `tests/test_stop_guard.sh::"one edit: silent"`,
  `tests/test_stop_guard.sh::"edits only: silent"`,
  `tests/test_stop_guard.sh::"long read-only run: silent"`,
  `tests/test_stop_guard.sh::"commit: decision"`,
  `tests/test_stop_guard.sh::"push: decision"`,
  `tests/test_stop_guard.sh::"pr create: decision"`,
  `tests/test_stop_guard.sh::"pr merge: decision"`,
  `tests/test_stop_guard.sh::"cooldown: default is 90 minutes, not 30"`,
  `tests/test_stop_guard.sh::"cooldown: env override shortens it"`,
  `tests/test_stop_guard.sh::"cooldown: new work inside cooldown is silent"`,
  `tests/test_stop_guard.sh::"cooldown: new work after cooldown blocks"`,
  `tests/test_stop_guard.sh::"cooldown: work 5 min after a write is silent"`,
  `tests/test_stop_guard.sh::"cooldown: write stamped in the future is ignored"`,
  `tests/test_stop_guard.sh::"unrecordable: no tool_use id is silent"`,
  `tests/test_stop_guard.sh::"unrecordable: unwritable state dir is silent"`,
  `tests/test_stop_guard.sh::"unattended: claude -p env is silent"` and
  `tests/test_stop_guard.sh::"unattended: sdk entrypoint without attended flag is silent"`
  (test suite only). No test runs the hook inside a real Claude Code session.

### The reason names the resolved context, or sends the model to `/setup`

`scripts/stop_guard.py::build_reason()` names world, project and tasks path for
a resolved repo, notes when the world came from path root, points an
`UNRESOLVED` repo to the onboarding flow
(`scripts/stop_guard.py::"Run the onboarding flow"`), and makes no world claim
when the resolver itself failed `[verified]`.

enforcement: `tests/test_stop_guard.sh::"unresolved: reason points to /setup"`
  and `tests/test_stop_guard.sh::"resolve-context failure: no world claim in reason"`
  (test suite only).

## Native worklog panel

Every claim in this section is `[verified]`, and every
`enforcement:` here runs only under `make test-native` (`claude plugin test`
with fixtures for Outline, processes and commands), never in a live session.

### `hooks/hooks.json` names one hooks module beside the classic hooks

`hooks/hooks.json::"modules"` lists `./register.tsx` and keeps the `hooks` key
with the classic `SessionStart` and `Stop` entries unchanged. How a build without
Mods treats the `modules` key has not been run. The manifest names the state contract
(`.claude-plugin/plugin.json::"types"`, owned by `packaging`).

enforcement: `claude plugin validate .` under `Makefile::test-native` (reports
  the module's hooks and calls); `tests/test_structure.sh::"hooks.json missing wrapped SessionStart"`
  still guards the classic shape.

### Entry points: `/worklog-persist:show` and the exact phrase

A `command.run` hook on `hooks/register.tsx::"worklog-persist:show"` answers the
command itself: it opens the pane and refreshes it, so the markdown body of
`commands/show.md` runs only where the module is not loaded. A `prompt.submit`
hook opens the pane for the exact prompt `hooks/register.tsx::"show worklog panel"`
(trimmed, any case) and drops that prompt; any other text passes unchanged.
Both answer with what `$.ui.open` resolved: "Opened the worklog panel." only
when `isPlaced` is true, otherwise the engine's `reason` and no Outline read.
An unplaced open clears the previous snapshot before a surface can later render
it (`hooks/register.tsx::open()`).

enforcement: `tests/worklog-panel.test.tsx::"the show command opens the pane and reads the current project"`,
  `tests/worklog-panel.test.tsx::"the exact phrase opens the pane; other text passes unchanged"`,
  `tests/worklog-panel.test.tsx::"an unplaced pane is reported with its reason, not as opened"`,
  `tests/worklog-panel.test.tsx::"an unplaced reopen clears the old snapshot before a surface later attaches"`.

### State contract: one `worklog-persist.panel` value, shape tag `panel-2`

`types/index.d.ts::"WorklogPanel"` declares the session state the pane draws
from. The atom carries `hooks/register.tsx::"panel-2"`; a value stored under
another tag (an older version, before a reload) reads as empty. A field change
must change the tag.

enforcement: `claude plugin validate .` holds the module's state reads and
  writes to the contract;
  `tests/worklog-panel.test.tsx::"a value an older version stored is declined"`.

### Outline is read with three tools, never written

The panel calls `list_collections`, `list_collection_documents` and `fetch`
through `$.mcp.call`, on the first prefix whose three tools are all listed:
`mcp__outline__` or `mcp__plugin_worklog-persist_outline__`
(`hooks/worklog-panel.ts::pickOutline()`). It names no write tool.

enforcement: `tests/worklog-panel.test.tsx::"a missing project folder is named and nothing is created"`
  (only read tools are called); `tests/worklog-panel.test.tsx::"the plugin-scoped Outline tools are used when they are the ones connected"`.

### Result formats the decoders accept

- `list_collections`: each text block one JSON collection `{id, name}`, or a
  JSON array of them; `[]` is a valid empty list
  (`hooks/worklog-panel.ts::decodeCollections()`). Paged by 100 until a short page.
- `list_collection_documents`: one JSON node `{id, title, url, children}` per
  text block, nested (`hooks/worklog-panel.ts::decodeTree()`). This shape was
  read from saved outputs of earlier sessions on this machine
  `[historical: 2026-10-23, saved list_collection_documents results under the Claude Code projects folder]`,
  and confirmed by one live read-only call on this project's collection, where
  every node carried `children` as an array and leaves `[]`
  `[historical: 2026-10-23, live list_collection_documents response checked by the lead session]`.
- `fetch`: a JSON block `{document: {id, title, parentDocumentId, ...}, breadcrumb}`,
  then the Markdown body as separate text blocks; `document.text` is used only
  when no body block follows (`hooks/worklog-panel.ts::decodeFetch()`).
- Every node must carry `children` as an array; `null` or a missing key is an
  error. A list result with no content blocks at all is an error; an empty list
  must arrive as an explicit `[]`.
- A `structuredContent` list is used when present and passes the same shape
  checks. Anything else, and any `isError` result, is a `DecodeError` shown as
  a failure.

enforcement: `tests/worklog-panel.test.tsx::"a malformed collections result is an error, not an empty project"`,
  `tests/worklog-panel.test.tsx::"an isError tree result is shown as a failure"`,
  `tests/worklog-panel.test.tsx::"a tree node without an id is an error"`,
  `tests/worklog-panel.test.tsx::"null children is a malformed tree, not an empty folder"`,
  `tests/worklog-panel.test.tsx::"a result with no content blocks is an error, not an empty list"`,
  `tests/worklog-panel.test.tsx::"an explicit [] is a valid empty tree"`.

### Pinned task and preview status

`hooks/register.tsx::updateStatus()` uses the mod's own `$.ui.status` slot below
the prompt, not the user's global status-line configuration. A confirmed project
shows `Task: <slug>`, or `Task: not selected`; a ready preview adds
`Preview: <title>`. Preview never changes the active task. Every committed panel
state update goes through `hooks/register.tsx::updatePanel()`, which updates the
status afterwards; reload restores it from compatible session state. Project
refreshes, project-read errors, unresolved scope and a cleared or moved session
remove the line.
These are `[verified]` claims.

enforcement: `tests/worklog-panel.test.tsx::"the pinned status follows the task and labels document previews separately"`,
  `tests/worklog-panel.test.tsx::"previewing a document does not invent an active task in the status"`,
  `tests/worklog-panel.test.tsx::"the pinned status clears during refresh and when the project becomes ignored"`,
  `tests/worklog-panel.test.tsx::"a reload restores the chosen task status but a directory change clears it"`.

### Large native MCP results may be saved by the host

`hooks/outline-result.ts::readOutline()` wraps all three Outline reads. A large
native response can contain a host notice rather than JSON, even with
`isError: false`; the complete content-block array is stored in the file named
by that notice. This boundary was reproduced through the running Mods API,
not a model-tool result `[historical: 2026-10-23, native read-only probe]`.

Recovery accepts only the exact host-notice format and a file for the requested
server and tool in the current session's `tool-results` directory beneath
`CLAUDE_CONFIG_DIR/projects`, or `HOME/.claude/projects`. It checks lexical and
resolved paths, file kind, links and the native 4 MiB read limit before reading.
The saved content must be a JSON array of text blocks; normal decoders still
validate the recovered data. Unknown notices, unreadable files, wrong paths,
oversized files and malformed payloads remain visible errors, not empty data.
These are `[verified]` claims.

The same recovery code decoded a real current-project tree through native MCP
and native file IO `[historical: 2026-10-23, live read-only probe]`.

enforcement: `tests/worklog-panel.test.tsx::"a host-saved collection tree is decoded through native file IO"`,
  `tests/worklog-panel.test.tsx::"host-saved fetch preserves metadata and the complete body for explicit loading"`,
  `tests/worklog-panel.test.tsx::"host-saved collection listings use the same bounded recovery"`,
  `tests/worklog-panel.test.tsx::"a saved tree reference outside its session and tool is refused"`,
  `tests/worklog-panel.test.tsx::"a saved result resolving outside the session directory is refused before reading"`,
  `tests/worklog-panel.test.tsx::"a saved result larger than native file IO permits is refused before reading"`,
  `tests/worklog-panel.test.tsx::"a corrupt saved payload remains an error rather than an empty project"`.

### Load appends one framed user row

`hooks/register.tsx::loadIntoSession()` appends the previewed document with
`$.session.append` as one `user` row built by
`hooks/worklog-panel.ts::frameForSession()`: the Outline id, title and project
path, a line saying it is untrusted data, then the full body. A body over
`hooks/worklog-panel.ts::LOAD_LIMIT` characters is refused, never cut. A `deny`
or a rejected append is shown; nothing else is reported as loaded.

enforcement: `tests/worklog-panel.test.tsx::"explicit Load appends the full document with its id as untrusted data"`,
  `tests/worklog-panel.test.tsx::"a refused append is shown as a failure"`,
  `tests/worklog-panel.test.tsx::"long bodies are paged, and an oversized body is not loaded"`.

### Actions run this plugin's own commands

The action buttons are the verbs `$.command.list()` reports as
`worklog-persist:<verb>` (`hooks/register.tsx::listCommands()`); a verb not
listed is named as unavailable and not offered. `hooks/register.tsx::runAction()`
calls `$.command.run` with the chosen arguments: the active task's slug for
`load`, `checkpoint`, `handoff`, `complete` and `dry-run`, a typed slug for
`start`, `on|off|status` for `off`, nothing for `setup`. A resolved
`$.command.run` is shown as dispatched and "not confirmed as written".

enforcement: `tests/worklog-panel.test.tsx::"actions come from the command list; a missing one is not offered"`,
  `tests/worklog-panel.test.tsx::"a task action needs a chosen task and forwards its slug"`,
  `tests/worklog-panel.test.tsx::"start takes a typed slug and rejects a bad one"`.
