#!/usr/bin/env python3
"""Resolve the identity and Outline address of the current work item.

Prints JSON. The KB structure comes from the plugin's own YAML config
(`$WORKLOG_CONFIG`, else ~/.config/worklog-persist/config.yaml): collections come
from its `outline:` block, and a repo declared under `worlds[].projects[]` gets
its world, project name and optional `kb_folder` from there. No world name is
hardcoded. Only scripts/config_add.py writes that file.

World precedence: (1) a project declared in the config; (2) $WORKLOG_WORLD;
(3) path root: the config world whose declared repos' common ancestor is the
deepest ancestor-or-equal of this repo (a tie between different worlds at that
depth stays unresolved); (4) "UNRESOLVED", which the caller turns into the
onboarding flow. An ignored repo gets no world from tiers 2 or 3. Outside any git
repo the project is "workspace". Usage: resolve_context.py [task-slug]
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

UNRESOLVED = "UNRESOLVED"
# Plain kebab slug, or a ticket-prefixed one (AD-163-uat-checklist).
SLUG_RE = re.compile(r"^(?:[A-Z][A-Z0-9]*-[0-9]+-)?[a-z0-9]+(?:-[a-z0-9]+)*$")
# Used only when the config's `outline:` block omits a key; the config always
# wins. Neutral placeholders, not any operator's real collection names: set
# `outline.root_collection` (and the other two keys, if wanted) in config.yaml
# to route to your own Outline instance. See README.md and
# docs/persistence-protocol/CONTRACTS.md ("Plugin config file").
DEFAULT_OUTLINE = {
    "root_collection": "Worklog",
    "global_collection": "Claude's Notebook",
    "archive_collection": "Archive",
}


def git(*args, cwd):
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def canonical_repo(cwd):
    """Main checkout of the repo, so a linked worktree maps to its real project."""
    top = git("rev-parse", "--show-toplevel", cwd=cwd)
    if not top:
        return None, None
    git_dir = git("rev-parse", "--absolute-git-dir", cwd=cwd)
    common = git("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=cwd)
    main = Path(top)
    if git_dir and common and Path(git_dir).resolve() != Path(common).resolve():
        # Linked worktree: the first `git worktree list` record is the main checkout.
        first = git("worktree", "list", "--porcelain", cwd=cwd).split("\n", 1)[0]
        if first.startswith("worktree "):
            main = Path(first[len("worktree "):])
    return Path(top), main.resolve()


def config_path():
    return Path(os.environ.get("WORKLOG_CONFIG")
                or Path.home() / ".config/worklog-persist/config.yaml")


def load_config(path):
    """Return (config dict or None, error string or None). Never raises."""
    if not path.is_file():
        return None, f"config not found: {path}"
    try:
        import yaml
    except ImportError:
        return None, "config unreadable: PyYAML is not installed"
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        data = {} if data is None else data
    except Exception as e:  # noqa: BLE001 - report, the caller decides
        return None, f"config unreadable: {e}"
    error = shape_error(data)
    return (None, f"config malformed: {error}") if error else (data, None)


def shape_error(data):
    """Check only the shape this script reads, so a bad config cannot crash it."""
    if not isinstance(data, dict):
        return "not a mapping"
    if not isinstance(data.get("outline") or {}, dict):
        return "`outline` is not a mapping"
    worlds = data.get("worlds") or []
    if not isinstance(worlds, list) or not all(isinstance(w, dict) for w in worlds):
        return "`worlds` is not a list of mappings"
    for w in worlds:
        projects = w.get("projects") or []
        if not isinstance(projects, list) or not all(isinstance(x, dict) for x in projects):
            return f"world {w.get('name')!r}: `projects` is not a list of mappings"
    if not isinstance(data.get("ignore") or [], list):
        return "`ignore` is not a list"
    return None


def expand(p):
    """Absolute real path, or None when it cannot be expanded (e.g. `~nouser`)."""
    try:
        return Path(str(p)).expanduser().resolve()
    except (OSError, RuntimeError):
        return None


def find_project(config, repo):
    for w in config.get("worlds") or []:
        for p in w.get("projects") or []:
            if p.get("repo") and expand(p["repo"]) == repo:
                return w.get("name"), p
    return None, None


def world_repo_roots(config):
    """{world name: common ancestor of its declared, expanded repo paths}.

    A world with no repos contributes no root.
    """
    repos_by_world = {}
    for w in config.get("worlds") or []:
        name = w.get("name")
        if not name:
            continue
        for p in w.get("projects") or []:
            rp = expand(p.get("repo")) if p.get("repo") else None
            if rp:
                repos_by_world.setdefault(name, []).append(rp)
    roots = {}
    for name, paths in repos_by_world.items():
        try:
            roots[name] = Path(os.path.commonpath([str(p) for p in paths]))
        except ValueError:
            continue  # e.g. paths on different drives; not a usable root
    return roots


def path_root_world(roots, target):
    """The world whose root is the deepest ancestor-or-equal of `target`.

    None both when nothing qualifies and when two or more different worlds tie
    for the deepest match: ambiguous, so it is never guessed.
    """
    matches = [(len(root.parts), name) for name, root in roots.items()
               if root == target or root in target.parents]
    if not matches:
        return None
    best_depth = max(depth for depth, _name in matches)
    tied = {name for depth, name in matches if depth == best_depth}
    return tied.pop() if len(tied) == 1 else None


def main(argv):
    slug = argv[1] if len(argv) > 1 else ""
    if slug and not SLUG_RE.match(slug):
        print(f"resolve-context: invalid task slug '{slug}' "
              "(want kebab-case, optionally TICKET-123- prefixed)", file=sys.stderr)
        return 2

    cwd = Path.cwd()
    worktree, repo_root = canonical_repo(cwd)
    is_git = worktree is not None
    if worktree:
        branch = git("rev-parse", "--abbrev-ref", "HEAD", cwd=worktree) or "UNKNOWN"
        remote = git("remote", "get-url", "origin", cwd=worktree)
    else:
        worktree, repo_root, branch, remote = cwd, cwd.resolve(), "UNKNOWN", ""
    repo = re.sub(r"\.git$", "", remote.rstrip("/").rsplit("/", 1)[-1].rsplit(":", 1)[-1]) \
        if remote else repo_root.name

    cpath = config_path()
    config, config_error = load_config(cpath)
    outline = dict(DEFAULT_OUTLINE)
    if config:
        outline.update({k: v for k, v in (config.get("outline") or {}).items()
                        if k in DEFAULT_OUTLINE and v})
    # A default root names no real collection, so bootstrap must ask instead of creating it.
    root_source = "config" if outline["root_collection"] != DEFAULT_OUTLINE["root_collection"] \
        or ((config or {}).get("outline") or {}).get("root_collection") else "default"

    # Outside git the directory name says nothing stable about the work.
    world, project, kb_folder, source = None, repo if is_git else "workspace", None, "fallback"
    ignored = False
    if config:
        w, p = find_project(config, repo_root)
        if p:
            world, project, kb_folder, source = w, p.get("name") or repo, p.get("kb_folder"), "config"
        ignored = any(i and (i == repo_root or i in repo_root.parents)
                      for i in map(expand, config.get("ignore") or []))
    # An ignored repo has no Outline folder by operator decision; inference (env,
    # path root) must not add one.
    if not world and not ignored and os.environ.get("WORKLOG_WORLD"):
        world, source = os.environ["WORKLOG_WORLD"], "env"
    if not world and not ignored and config:
        w = path_root_world(world_repo_roots(config), repo_root)
        if w:
            world, source = w, "path-root"
    world = world or UNRESOLVED

    root = outline["root_collection"]
    kb_path = kb_folder or (f"{root}/{world}/{project}" if world != UNRESOLVED else None)

    print(json.dumps({
        "repo": repo,
        "repo_root": str(repo_root),
        "project": project,
        "world": world,
        "world_source": source,
        "candidate_worlds": [w.get("name") for w in (config or {}).get("worlds") or []],
        "ignored": ignored,
        "branch": branch,
        "worktree": str(worktree),
        "task_slug": slug,
        "root_collection": root,
        "root_collection_source": root_source,
        "global_collection": outline["global_collection"],
        "archive_collection": outline["archive_collection"],
        "kb_path": kb_path,
        "tasks_path": f"{kb_path}/Tasks" if kb_path else None,
        "record_path": f"{kb_path}/Tasks/{slug}" if kb_path and slug else None,
        "config": str(cpath) if config else None,
        "config_path": str(cpath),
        "config_error": config_error,
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
