#!/usr/bin/env bash
# scripts/config-add.sh: the only sanctioned writer of the plugin config.
# Every case runs against a scratch WORKLOG_CONFIG. Run: bash tests/test_config_add.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADD="$ROOT/scripts/config-add.sh"
RESOLVE="$ROOT/scripts/resolve-context.sh"
fails=0
check() { if [ "$2" != "$3" ]; then echo "FAIL: $1 (want '$3', got '$2')"; fails=$((fails+1)); else echo "ok: $1"; fi; }
sum() { if [ -f "$1" ]; then shasum "$1" | cut -d' ' -f1; else echo absent; fi; }
repos() { [ -f "$1" ] || { echo absent; return; }; python3 -c 'import sys,yaml;print(" ".join(p["repo"] for w in yaml.safe_load(open(sys.argv[1]))["worlds"] for p in w["projects"]))' "$1"; }
ident() { python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["world"],d["world_source"],d["project"],d["kb_path"],d["ignored"])'; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
unset WORKLOG_WORLD || true
cfg="$tmp/nested/dir/config.yaml"
export WORKLOG_CONFIG="$cfg"
for r in one two three; do
  mkdir -p "$tmp/$r" && git -C "$tmp/$r" init -q && git -C "$tmp/$r" commit -q --allow-empty -m init
done
one="$(cd "$tmp/one" && pwd -P)"

# 1. Missing file and parent dirs are created; the resolver then routes the repo.
rc=0; bash "$ADD" project --world Alpha --name proj-one --repo "$tmp/one" >/dev/null || rc=$?
check "create file: exit 0" "$rc" "0"
check "create file: exists" "$(test -f "$cfg" && echo yes)" "yes"
check "create file: resolves" "$(cd "$tmp/one" && bash "$RESOLVE" | ident)" "Alpha config proj-one Worklog/Alpha/proj-one False"

# 2. Re-adding the same declaration is a no-op: exit 0 and the file is untouched.
before="$(sum "$cfg")"
rc=0; out="$(bash "$ADD" project --world Alpha --name proj-one --repo "$tmp/one")" || rc=$?
check "idempotent re-add: exit 0" "$rc" "0"
check "idempotent re-add: byte-identical" "$(sum "$cfg")" "$before"
check "idempotent re-add: says so" "$(grep -c 'no change' <<<"$out")" "1"

# 3. The same repo under a different world is an error, never a silent move.
rc=0; bash "$ADD" project --world Beta --name proj-one --repo "$tmp/one" >/dev/null 2>&1 || rc=$?
check "conflict: non-zero exit" "$([ "$rc" != 0 ] && echo yes)" "yes"
check "conflict: file untouched" "$(sum "$cfg")" "$before"

# 4. A second project and a kb_folder keep the first entry intact.
bash "$ADD" project --world Alpha --name proj-two --repo "$tmp/two" --kb-folder "KB/Alpha/custom" >/dev/null || true
check "second project: first kept" "$(cd "$tmp/one" && bash "$RESOLVE" | ident)" "Alpha config proj-one Worklog/Alpha/proj-one False"
check "second project: kb_folder" "$(cd "$tmp/two" && bash "$RESOLVE" | ident)" "Alpha config proj-two KB/Alpha/custom False"
check "one world entry" "$(python3 -c 'import sys,yaml;print([w["name"] for w in yaml.safe_load(open(sys.argv[1]))["worlds"]])' "$cfg")" "['Alpha']"

# 5. An ignore entry makes the repo ignored; repeating it is a no-op.
bash "$ADD" ignore --repo "$tmp/three" >/dev/null || true
check "ignore: resolves ignored" "$(cd "$tmp/three" && WORKLOG_WORLD=E bash "$RESOLVE" | ident)" "UNRESOLVED fallback three None True"
before="$(sum "$cfg")"
bash "$ADD" ignore --repo "$tmp/three" >/dev/null || true
check "ignore: idempotent" "$(sum "$cfg")" "$before"
# A declared repo cannot also be ignored, and an ignored one cannot be declared.
rc=0; bash "$ADD" ignore --repo "$tmp/one" >/dev/null 2>&1 || rc=$?
check "ignore declared repo: refused" "$([ "$rc" != 0 ] && echo yes) $(sum "$cfg")" "yes $before"
rc=0; bash "$ADD" project --world Alpha --name three --repo "$tmp/three" >/dev/null 2>&1 || rc=$?
check "declare ignored repo: refused" "$([ "$rc" != 0 ] && echo yes) $(sum "$cfg")" "yes $before"

# 6. Paths are stored resolved, so the resolver matches them from any spelling.
check "stored path is resolved" "$(python3 -c 'import sys,yaml;print(yaml.safe_load(open(sys.argv[1]))["worlds"][0]["projects"][0]["repo"])' "$cfg")" "$one"

# 7. No temp file is left next to the config after a write.
check "atomic write leaves no temp file" "$(find "$(dirname "$cfg")" -type f | wc -l | tr -d ' ')" "1"

# 8. A file it cannot parse, or with the wrong shape, is refused and left byte-identical.
printf 'worlds:\n  - name: [unclosed\n' > "$tmp/garbage.yaml"
before="$(sum "$tmp/garbage.yaml")"
rc=0; WORKLOG_CONFIG="$tmp/garbage.yaml" bash "$ADD" project --world A --name n --repo "$tmp/one" >/dev/null 2>&1 || rc=$?
check "unparseable file refused" "$([ "$rc" != 0 ] && echo yes) $(sum "$tmp/garbage.yaml")" "yes $before"
printf 'outline: [x]\nworlds: [a, b]\nignore: 3\n' > "$tmp/bad.yaml"
before="$(sum "$tmp/bad.yaml")"
rc=0; WORKLOG_CONFIG="$tmp/bad.yaml" bash "$ADD" ignore --repo "$tmp/one" >/dev/null 2>&1 || rc=$?
check "malformed file refused" "$([ "$rc" != 0 ] && echo yes) $(sum "$tmp/bad.yaml")" "yes $before"

# 9. Without PyYAML it reports the cause and writes nothing.
mkdir -p "$tmp/noyaml" && echo 'raise ImportError("stub")' > "$tmp/noyaml/yaml.py"
rc=0; err="$(PYTHONPATH="$tmp/noyaml" WORKLOG_CONFIG="$tmp/fresh.yaml" bash "$ADD" ignore --repo "$tmp/one" 2>&1)" || rc=$?
check "no PyYAML: refused, nothing written" "$([ "$rc" != 0 ] && echo yes) $(sum "$tmp/fresh.yaml")" "yes absent"
check "no PyYAML: names the cause" "$(grep -c 'PyYAML' <<<"$err")" "1"

# 10. Bad arguments are rejected before any write.
rc=0; WORKLOG_CONFIG="$tmp/fresh.yaml" bash "$ADD" project --world 'A/B' --name n --repo "$tmp/one" >/dev/null 2>&1 || rc=$?
check "world with slash refused" "$([ "$rc" != 0 ] && echo yes) $(sum "$tmp/fresh.yaml")" "yes absent"

# 11. A symlinked config (dotfiles) stays a symlink; the entry lands in its target.
mkdir -p "$tmp/dotfiles" "$tmp/linkdir"
printf 'worlds: []\n' > "$tmp/dotfiles/config.yaml" && chmod 600 "$tmp/dotfiles/config.yaml"
ln -s "$tmp/dotfiles/config.yaml" "$tmp/linkdir/config.yaml"
rc=0; WORKLOG_CONFIG="$tmp/linkdir/config.yaml" bash "$ADD" project --world Alpha --name linked --repo "$tmp/one" >/dev/null 2>&1 || rc=$?
check "symlink: exit 0" "$rc" "0"
check "symlink: still a symlink" "$(test -L "$tmp/linkdir/config.yaml" && echo yes)" "yes"
check "symlink: target has entry" "$(grep -c 'name: linked' "$tmp/dotfiles/config.yaml")" "1"
check "symlink: target mode kept" "$(python3 -c 'import os,sys;print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$tmp/dotfiles/config.yaml")" "0o600"
check "symlink: no temp file left" "$(find "$tmp/dotfiles" "$tmp/linkdir" -name '*.tmp' | wc -l | tr -d ' ')" "0"

# 12. A linked worktree is stored as its main checkout, so the resolver matches it.
git -C "$tmp/one" worktree add -q "$tmp/one-wt" -b wt
wcfg="$tmp/wt.yaml"
rc=0; WORKLOG_CONFIG="$wcfg" bash "$ADD" project --world Alpha --name proj-one --repo "$tmp/one-wt" >/dev/null 2>&1 || rc=$?
check "worktree: exit 0" "$rc" "0"
check "worktree: resolves from worktree" "$(cd "$tmp/one-wt" && WORKLOG_CONFIG="$wcfg" bash "$RESOLVE" | ident)" "Alpha config proj-one Worklog/Alpha/proj-one False"
check "worktree: resolves from main" "$(cd "$tmp/one" && WORKLOG_CONFIG="$wcfg" bash "$RESOLVE" | ident)" "Alpha config proj-one Worklog/Alpha/proj-one False"
before="$(sum "$wcfg")"
rc=0; out="$(WORKLOG_CONFIG="$wcfg" bash "$ADD" project --world Alpha --name proj-one --repo "$tmp/one")" || rc=$?
check "worktree then main: same repo, no change" "$rc $(sum "$wcfg") $(grep -c 'no change' <<<"$out")" "0 $before 1"
check "worktree: stored repo is main checkout" "$(repos "$wcfg")" "$one"

# 13. A path typed in another case (case-insensitive disk) is stored in the on-disk case.
mkdir -p "$tmp/MyRepo" && git -C "$tmp/MyRepo" init -q
if [ -d "$tmp/myrepo" ]; then
  ccfg="$tmp/case.yaml"
  rc=0; err="$(WORKLOG_CONFIG="$ccfg" bash "$ADD" project --world Alpha --name my --repo "$tmp/myrepo" 2>&1 >/dev/null)" || rc=$?
  check "case mismatch: exit 0, no traceback" "$rc $(grep -c Traceback <<<"$err" || true)" "0 0"
  check "case mismatch: stored in on-disk case" "$(repos "$ccfg")" "$(cd "$tmp/MyRepo" && pwd -P)"
else
  echo "skip: case mismatch (case-sensitive filesystem)"
fi

# 14. Without a git binary the repo is stored as given, never a traceback.
mkdir -p "$tmp/nogit-bin"
py="$(python3 -c 'import sys;print(sys.executable)')"
check "no git: git really absent" "$(PATH="$tmp/nogit-bin" command -v git || echo none)" "none"
gcfg="$tmp/nogit.yaml"
rc=0; err="$(PATH="$tmp/nogit-bin" WORKLOG_CONFIG="$gcfg" "$py" "$ROOT/scripts/config_add.py" project --world Alpha --name ng --repo "$tmp/two" 2>&1 >/dev/null)" || rc=$?
check "no git: exit 0, no traceback" "$rc $(grep -c Traceback <<<"$err" || true)" "0 0"
check "no git: stored as given" "$(repos "$gcfg")" "$(cd "$tmp/two" && pwd -P)"

# 15. A worktree path stored by older code is compared as its main checkout.
wt="$(cd "$tmp/one-wt" && pwd -P)"
scfg="$tmp/stale.yaml"
printf 'worlds:\n  - name: A\n    projects:\n      - {name: p, repo: %s}\n' "$wt" > "$scfg"
before="$(sum "$scfg")"
rc=0; WORKLOG_CONFIG="$scfg" bash "$ADD" project --world B --name p --repo "$tmp/one" >/dev/null 2>&1 || rc=$?
check "stale worktree entry: other world refused" "$([ "$rc" != 0 ] && echo yes) $(sum "$scfg")" "yes $before"
rc=0; WORKLOG_CONFIG="$scfg" bash "$ADD" project --world A --name p --repo "$tmp/one" >/dev/null 2>&1 || rc=$?
check "stale worktree entry: same entry rewritten" "$rc $(repos "$scfg")" "0 $one"
check "stale worktree entry: now resolves" "$(cd "$tmp/one" && WORKLOG_CONFIG="$scfg" bash "$RESOLVE" | ident)" "A config p Worklog/A/p False"
icfg="$tmp/stale-ignore.yaml"
printf 'ignore:\n  - %s\n' "$wt" > "$icfg"
before="$(sum "$icfg")"
rc=0; WORKLOG_CONFIG="$icfg" bash "$ADD" project --world A --name p --repo "$tmp/one" >/dev/null 2>&1 || rc=$?
check "stale worktree ignore: declare refused" "$([ "$rc" != 0 ] && echo yes) $(sum "$icfg")" "yes $before"
rc=0; WORKLOG_CONFIG="$icfg" bash "$ADD" ignore --repo "$tmp/one" >/dev/null 2>&1 || rc=$?
check "stale worktree ignore: same entry rewritten" "$rc $(python3 -c 'import sys,yaml;print(*yaml.safe_load(open(sys.argv[1]))["ignore"])' "$icfg")" "0 $one"

# 16. A worktree subdir missing from the main checkout is refused, not stored.
mkdir -p "$tmp/one-wt/only-wt"
rc=0; err="$(WORKLOG_CONFIG="$tmp/sub.yaml" bash "$ADD" ignore --repo "$tmp/one-wt/only-wt" 2>&1 >/dev/null)" || rc=$?
check "worktree-only subdir: refused cleanly" "$rc $(grep -c '^config-add:' <<<"$err") $(sum "$tmp/sub.yaml")" "2 1 absent"

# 17. A stale worktree entry next to the canonical one is dropped, never duplicated.
dcfg="$tmp/dup.yaml"
printf 'worlds:\n  - name: A\n    projects:\n      - {name: p, repo: %s}\n      - {name: p, repo: %s}\n' "$wt" "$one" > "$dcfg"
rc=0; WORKLOG_CONFIG="$dcfg" bash "$ADD" project --world A --name p --repo "$tmp/one" >/dev/null 2>&1 || rc=$?
check "stale beside canonical project: one entry left" "$rc $(repos "$dcfg")" "0 $one"
dicfg="$tmp/dup-ignore.yaml"
printf 'ignore:\n  - %s\n  - %s\n' "$wt" "$one" > "$dicfg"
rc=0; WORKLOG_CONFIG="$dicfg" bash "$ADD" ignore --repo "$tmp/one" >/dev/null 2>&1 || rc=$?
check "stale beside canonical ignore: one entry left" "$rc $(python3 -c 'import sys,yaml;print(*yaml.safe_load(open(sys.argv[1]))["ignore"])' "$dicfg")" "0 $one"

# 18. A stored path in another case (case-insensitive disk) still counts as that repo.
if [ -d "$tmp/myrepo" ]; then
  kcfg="$tmp/case-stored.yaml"
  printf 'worlds:\n  - name: A\n    projects:\n      - {name: m, repo: %s}\n' "$tmp/myrepo" > "$kcfg"
  before="$(sum "$kcfg")"
  rc=0; WORKLOG_CONFIG="$kcfg" bash "$ADD" project --world B --name m --repo "$tmp/MyRepo" >/dev/null 2>&1 || rc=$?
  check "stale case entry: other world refused" "$([ "$rc" != 0 ] && echo yes) $(sum "$kcfg")" "yes $before"
  rc=0; WORKLOG_CONFIG="$kcfg" bash "$ADD" project --world A --name m --repo "$tmp/MyRepo" >/dev/null 2>&1 || rc=$?
  check "stale case entry: rewritten to on-disk case" "$rc $(repos "$kcfg")" "0 $(cd "$tmp/MyRepo" && pwd -P)"
else
  echo "skip: stored case mismatch (case-sensitive filesystem)"
fi

[ "$fails" = 0 ] && echo "PASS test_config_add" || { echo "$fails failure(s)"; exit 1; }
