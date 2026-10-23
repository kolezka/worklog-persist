---
block: _root
doc: CONVENTIONS
verified_against: fcd9e31
verified_on: 2026-10-23
---

# Conventions

Rules every file under `docs/` follows. The job of this tree: **let someone
change or rewrite the plugin without re-reading all of its code.**

`tests/test_docs_layout.py` enforces every rule marked *(tested)* below. The rest
are convention.

---

## The pinned commit

Every file carries `verified_against:` in its front matter. All files pin the
**same** commit, and that commit must be an ancestor of `HEAD`. *(tested)*

A refresh re-pins every file in one pass. A per-file pin lets two pages describe
two different versions of the plugin.

---

## Cite by symbol, never by line number

```
scripts/persistence-state.sh::is_off()        ← shell function
scripts/redact.py::redact()                    ← Python function
install.sh::require_main_checkout()            ← shell function
```

For a file with no symbol, cite a **distinctive quoted phrase** from it:

```
hooks/hooks.json::"SessionStart"
.mcp.json::"OUTLINE_API_TOKEN"
```

Every `<path>::<symbol>` citation must name a tracked file that contains the symbol
or phrase. *(tested)* A `path:123` line citation is rejected. *(tested)* Line
numbers rot silently: they stay valid-looking and point at unrelated code.

---

## Evidence levels

One tag per claim-bearing sentence, at its end.

| Tag | Means |
|---|---|
| `[verified]` | The writer read the code, or ran the command, at the pinned commit |
| `[inferred]` | Derived from verified facts. The derivation is in the same sentence |
| `[assumption]` | Carried from another document or from memory without re-checking |
| `[historical: <date>, <source>]` | A past measurement that cannot be re-run from here |

A claim copied from another doc without re-checking is `[assumption]`, never
`[verified]`. Code is the primary source.

---

## Front matter

Every file. *(tested)*

```yaml
---
block: session-hook                 # must equal the folder path under docs/
doc: CONTRACTS                      # must equal the file name
verified_against: 2d0b8af
verified_on: 2026-10-18
owns: [hooks/, scripts/session-start.sh]   # README.md only
depends_on: [persistence-protocol]         # README.md only
---
```

`owns:` is the ownership record. An entry ending in `/` covers a directory.
Every tracked file is owned by exactly one block, or listed in `unassigned:` in
`docs/README.md`. *(tested)*

---

## Where a fact lives

**A fact lives in the block that owns the code enforcing it.** Any other block
gets one sentence and a link. Two copies of a fact diverge, and the reader cannot
tell which one is current.

---

## Enforcement is a field

Every entry in `CONTRACTS.md` carries an `enforcement:` line. The value is a
citation to the thing that enforces it, or the literal word `convention`:

```
enforcement: tests/test_install.sh::"default run is read-only"
enforcement: install.sh::check_structure()  (at --check time only)
enforcement: convention
```

Say how strong the check is: at run time, in the test suite only, or only when a
human remembers to run it.

---

## Ask the component where it writes

Never restate a path. Cite the resolver and its precedence chain.
`scripts/persistence-state.sh::state_dir()` resolves `XDG_STATE_HOME`, then
`$HOME/.local/state`, then appends `worklog-persist`. Writing
`~/.local/state/worklog-persist/off` records one machine, not the rule.

---

## No world names, no credentials

No tracked file names a knowledge-base world or holds a credential. Write
`<World>` for a world and `${OUTLINE_API_TOKEN}` for a secret.

---

## The file set

Five mandatory files per block, one optional. *(tested)*

| File | Holds |
|---|---|
| `README.md` | What the block is, its boundary, its `owns:` inventory, one mermaid diagram |
| `CONTRACTS.md` | Durable interfaces: file formats, env vars, entry points, each with `enforcement:` |
| `INVARIANTS.md` | Numbered behaviours that must hold, each with the defect it prevents |
| `GAPS.md` | Debt, unenforced boundaries, known bugs. `None known, verified <date>` is a valid body |
| `OPERATIONS.md` | Entry points, state paths and how they resolve, kill switches, stuck states |
| `DECISIONS.md` | *Optional.* Why it is shaped this way, and the alternatives that lost |

A change treats these as three different decisions: contracts keep their shape,
invariants keep their behaviour, gaps are free to fix.
