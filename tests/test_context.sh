#!/usr/bin/env bash
# Identity + world resolution tests for scripts/resolve-context.sh.
# World-agnostic: no world name is ever hardcoded; it comes from the plugin
# config, $WORKLOG_WORLD or the UNRESOLVED sentinel. Run: bash tests/test_context.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/resolve-context.sh"
fails=0
check() { if [ "$2" != "$3" ]; then echo "FAIL: $1 (want '$3', got '$2')"; fails=$((fails+1)); else echo "ok: $1"; fi; }
field() { python3 -c "import sys,json;print(json.load(sys.stdin)['$1'])"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# Isolate from the host config and env. The two legacy names are unset so the
# "old coupling ignored" case below controls them fully.
unset WORKLOG_WORLD KB_WORLD KB_MANIFEST || true
export WORKLOG_CONFIG="$tmp/none.yaml"

# Case 1: git repo, no remote -> project = dir name, world = UNRESOLVED sentinel.
mkdir -p "$tmp/myproj" && git -C "$tmp/myproj" init -q && git -C "$tmp/myproj" commit -q --allow-empty -m init
out="$(cd "$tmp/myproj" && WORKLOG_WORLD='' bash "$SCRIPT")"
check "no-remote project" "$(printf '%s' "$out" | field project)" "myproj"
check "no-remote world sentinel" "$(printf '%s' "$out" | field world)" "UNRESOLVED"
check "missing config reported" "$(printf '%s' "$out" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["config"],d["config_error"])')" \
  "None config not found: $tmp/none.yaml"

# Case 2: WORKLOG_WORLD overrides -> proves world is NOT hardcoded.
out="$(cd "$tmp/myproj" && WORKLOG_WORLD=SomeWorld bash "$SCRIPT")"
check "WORKLOG_WORLD honored" "$(printf '%s' "$out" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["world"],d["world_source"])')" "SomeWorld env"

# Case 3: the old kb coupling is gone. A legacy world env var and a valid legacy
# manifest at the old path shape, named both by KB_MANIFEST and by the old
# default under $HOME, must all be ignored.
mkdir -p "$tmp/home/.config/kb"
cat > "$tmp/home/.config/kb/worlds.yaml" <<EOF
version: 1
worlds:
  - name: Legacy
    projects:
      - {name: legacy-name, repo: $tmp/myproj}
EOF
legacy() { python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["world"],d["world_source"],d.get("config"))'; }
check "old coupling ignored: KB_WORLD" \
  "$(cd "$tmp/myproj" && KB_WORLD=X bash "$SCRIPT" | legacy)" "UNRESOLVED fallback None"
check "old coupling ignored: KB_WORLD + KB_MANIFEST" \
  "$(cd "$tmp/myproj" && HOME="$tmp/home" KB_WORLD=X KB_MANIFEST="$tmp/home/.config/kb/worlds.yaml" bash "$SCRIPT" | legacy)" "UNRESOLVED fallback None"
# The old layout also had overlay manifests (worlds-*.yaml) next to the default
# path. One there that declares this repo must be ignored too.
mkdir -p "$tmp/home2/.config/kb"
cat > "$tmp/home2/.config/kb/worlds-overlay.yaml" <<EOF
worlds:
  - name: Overlay
    projects:
      - {name: overlay-name, repo: $tmp/myproj}
EOF
check "old coupling ignored: overlay next to old default" \
  "$(cd "$tmp/myproj" && HOME="$tmp/home2" bash "$SCRIPT" | legacy)" "UNRESOLVED fallback None"
# With WORKLOG_CONFIG unset the default is the plugin's own file under $HOME.
check "default config path" "$(cd "$tmp/myproj" && env -u WORKLOG_CONFIG HOME="$tmp/home" bash "$SCRIPT" | field config_path)" \
  "$tmp/home/.config/worklog-persist/config.yaml"

# Case 4: remote origin -> project = repo basename sans .git.
git -C "$tmp/myproj" remote add origin "git@github.com:acme/coolrepo.git"
out="$(cd "$tmp/myproj" && bash "$SCRIPT")"
check "remote project basename" "$(printf '%s' "$out" | field project)" "coolrepo"

# Case 5: valid kebab slug preserved.
out="$(cd "$tmp/myproj" && bash "$SCRIPT" my-task-123)"
check "valid slug" "$(printf '%s' "$out" | field task_slug)" "my-task-123"
out="$(cd "$tmp/myproj" && bash "$SCRIPT" AD-163-uat-checklist)"
check "ticket slug" "$(printf '%s' "$out" | field task_slug)" "AD-163-uat-checklist"

# Case 6: invalid slug rejected (exit 2).
rc=0; (cd "$tmp/myproj" && bash "$SCRIPT" "Bad_Slug") >/dev/null 2>&1 || rc=$?
check "invalid slug rejected" "$rc" "2"

# Config fixture: custom collections, a declared project whose name differs from
# the directory, a kb_folder override, and an ignored repo.
mkdir -p "$tmp/other" "$tmp/skipme"
git -C "$tmp/other" init -q && git -C "$tmp/other" commit -q --allow-empty -m init
git -C "$tmp/skipme" init -q && git -C "$tmp/skipme" commit -q --allow-empty -m init
cat > "$tmp/config.yaml" <<EOF
outline:
  root_collection: RootKB
  global_collection: Notebook
  archive_collection: Attic
worlds:
  - name: Alpha
    projects:
      - {name: declared-name, repo: $tmp/myproj}
  - name: Beta
    projects:
      - {name: other, repo: $tmp/other, kb_folder: RootKB/Beta/custom-folder}
ignore:
  - $tmp/skipme
EOF
export WORKLOG_CONFIG="$tmp/config.yaml"

# Case 7: declared repo -> world, name and collections from the config, which
# beats WORKLOG_WORLD.
out="$(cd "$tmp/myproj" && WORKLOG_WORLD=Wrong bash "$SCRIPT" t)"
check "config identity" "$(printf '%s' "$out" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["world"],d["world_source"],d["project"],d["record_path"],d["global_collection"],d["archive_collection"])')" \
  "Alpha config declared-name RootKB/Alpha/declared-name/Tasks/t Notebook Attic"
check "config path reported" "$(printf '%s' "$out" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["config"],d["config_error"])')" \
  "$tmp/config.yaml None"

# Case 8: a linked worktree maps to its main checkout's project, not its dir name.
git -C "$tmp/myproj" worktree add -q -b feat/x "$tmp/wt-elsewhere"
out="$(cd "$tmp/wt-elsewhere" && bash "$SCRIPT")"
check "worktree identity" "$(printf '%s' "$out" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["project"],d["branch"],d["repo_root"])')" \
  "declared-name feat/x $(cd "$tmp/myproj" && pwd -P)"

# A checkout whose git dir lives elsewhere is still its own main checkout.
mkdir -p "$tmp/store" && git init -q --separate-git-dir "$tmp/store/.git" "$tmp/sep"
check "separate git dir" "$(cd "$tmp/sep" && bash "$SCRIPT" | field repo_root)" "$(cd "$tmp/sep" && pwd -P)"

# Case 9: kb_folder override is used verbatim.
out="$(cd "$tmp/other" && bash "$SCRIPT" t)"
check "kb_folder override" "$(printf '%s' "$out" | field tasks_path)" "RootKB/Beta/custom-folder/Tasks"

# Case 10: an ignored repo is flagged, gets no world, and offers the candidates.
out="$(cd "$tmp/skipme" && bash "$SCRIPT")"
check "ignored repo" "$(printf '%s' "$out" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["ignored"],d["world"],d["kb_path"],",".join(d["candidate_worlds"]))')" \
  "True UNRESOLVED None Alpha,Beta"
# WORKLOG_WORLD must not route an ignored repo.
check "ignored beats WORKLOG_WORLD" "$(cd "$tmp/skipme" && WORKLOG_WORLD=E bash "$SCRIPT" | field kb_path)" "None"
# A repo below an ignored dir is ignored too.
mkdir -p "$tmp/skipme/sub" && git -C "$tmp/skipme/sub" init -q
check "nested ignored" "$(cd "$tmp/skipme/sub" && bash "$SCRIPT" | field ignored)" "True"

# A config with the wrong shape is reported, never a crash.
printf 'outline: [x]\nworlds: [a, b]\nignore: 3\n' > "$tmp/bad.yaml"
check "malformed config" "$(cd "$tmp/myproj" && WORKLOG_CONFIG="$tmp/bad.yaml" bash "$SCRIPT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["world"],d["config"],d["config_error"][:16])')" \
  "UNRESOLVED None config malformed"

# A file that is not YAML at all is reported, never a crash, and the env still works.
printf 'worlds:\n  - name: [unclosed\n' > "$tmp/garbage.yaml"
check "unparseable config" "$(cd "$tmp/myproj" && WORKLOG_CONFIG="$tmp/garbage.yaml" WORKLOG_WORLD=E bash "$SCRIPT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["world"],d["config"],d["config_error"][:17])')" \
  "E None config unreadable"

# Without PyYAML the config is reported unreadable, never a crash, and the env still works.
mkdir -p "$tmp/noyaml" && echo 'raise ImportError("stub")' > "$tmp/noyaml/yaml.py"
check "no PyYAML" "$(cd "$tmp/myproj" && PYTHONPATH="$tmp/noyaml" WORKLOG_WORLD=E bash "$SCRIPT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["world"],d["config"],d["config_error"])')" \
  "E None config unreadable: PyYAML is not installed"

# --- Path root: an undeclared repo takes the world whose declared repos it sits under ---
# Own directory and own config, so the fixtures above do not add roots.
cm="$tmp/cm"
mkdir -p "$cm/a/x1" "$cm/a/x2" "$cm/a/ignored-sub" "$cm/a/undeclared" "$cm/b1" "$cm/b2" "$cm/exact-project" "$cm/y"
for d in "$cm/a/x1" "$cm/a/x2" "$cm/a/ignored-sub" "$cm/a/undeclared" "$cm/b1" "$cm/b2" "$cm/exact-project" "$cm/y"; do
  git -C "$d" init -q && git -C "$d" commit -q --allow-empty -m init
done
cm="$(cd "$cm" && pwd -P)"
# WorldA's repos live under $cm/a (deep, narrow root); WorldB's directly under
# $cm (shallow, broad root). WorldC declares one repo that sits inside B's root.
cat > "$cm/config.yaml" <<EOF
worlds:
  - name: WorldA
    projects:
      - {name: x1, repo: $cm/a/x1}
      - {name: x2, repo: $cm/a/x2}
  - name: WorldB
    projects:
      - {name: b1, repo: $cm/b1}
      - {name: b2, repo: $cm/b2}
  - name: WorldC
    projects:
      - {name: exact-project, repo: $cm/exact-project}
ignore:
  - $cm/a/ignored-sub
EOF
pr() { python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["world"],d["world_source"],d["ignored"])'; }
export WORKLOG_CONFIG="$cm/config.yaml"

# The deepest root wins: under A's root beats B's broader one.
check "path-root: deepest root wins" "$(cd "$cm/a/undeclared" && bash "$SCRIPT" | pr)" "WorldA path-root False"
check "path-root: broader root" "$(cd "$cm/y" && bash "$SCRIPT" | pr)" "WorldB path-root False"
# An exact declaration beats path root even inside another world's root.
check "declaration beats path-root" "$(cd "$cm/exact-project" && bash "$SCRIPT" | pr)" "WorldC config False"
# WORKLOG_WORLD is tier 2, so it beats path root.
check "WORKLOG_WORLD beats path-root" "$(cd "$cm/a/undeclared" && WORKLOG_WORLD=E bash "$SCRIPT" | pr)" "E env False"
# An ignored repo gets no world from path root, even inside a world's root.
check "ignored beats path-root" "$(cd "$cm/a/ignored-sub" && bash "$SCRIPT" | pr)" "UNRESOLVED fallback True"
# Outside every declared root nothing is inferred.
mkdir -p "$tmp/cm-outside/proj" && git -C "$tmp/cm-outside/proj" init -q && git -C "$tmp/cm-outside/proj" commit -q --allow-empty -m init
check "outside every root" "$(cd "$tmp/cm-outside/proj" && bash "$SCRIPT" | pr)" "UNRESOLVED fallback False"
# Candidates come from the one config.
check "candidate worlds from config" "$(cd "$cm/y" && bash "$SCRIPT" | python3 -c 'import sys,json;print(",".join(json.load(sys.stdin)["candidate_worlds"]))')" "WorldA,WorldB,WorldC"

# Two different worlds tied at the same root depth are ambiguous, never guessed.
tie="$tmp/tie"
mkdir -p "$tie/shared/proj/sub"
git -C "$tie/shared/proj/sub" init -q && git -C "$tie/shared/proj/sub" commit -q --allow-empty -m init
cat > "$tie/config.yaml" <<EOF
worlds:
  - name: T1
    projects:
      - {name: t1, repo: $tie/shared/proj}
  - name: T2
    projects:
      - {name: t2, repo: $tie/shared/proj}
EOF
check "equal-depth tie is ambiguous" "$(cd "$tie/shared/proj/sub" && WORKLOG_CONFIG="$tie/config.yaml" bash "$SCRIPT" | pr)" "UNRESOLVED fallback False"

# A directory with no git repo at all resolves project "workspace", never its basename.
mkdir -p "$tmp/not-a-repo"
check "non-git project workspace" "$(cd "$tmp/not-a-repo" && WORKLOG_CONFIG="$tmp/none.yaml" bash "$SCRIPT" | field project)" "workspace"

# The root collection says whether a config named it; only the default must never be created.
check "root from default without config" "$(cd "$tmp/myproj" && WORKLOG_CONFIG="$tmp/none.yaml" bash "$SCRIPT" | field root_collection_source)" "default"
check "root from config" "$(cd "$tmp/myproj" && WORKLOG_CONFIG="$tmp/config.yaml" bash "$SCRIPT" | field root_collection_source)" "config"
printf 'worlds:\n  - name: Alpha\n    projects:\n      - {name: p, repo: %s}\n' "$tmp/myproj" > "$tmp/no-outline.yaml"
check "config without outline block uses default root" "$(cd "$tmp/myproj" && WORKLOG_CONFIG="$tmp/no-outline.yaml" bash "$SCRIPT" | field root_collection_source)" "default"

[ "$fails" = 0 ] && echo "PASS test_context" || { echo "$fails failure(s)"; exit 1; }
