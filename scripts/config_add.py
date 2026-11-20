#!/usr/bin/env python3
"""Add one entry to the worklog-persist config. The only sanctioned writer.

Usage:
  config_add.py project --world W --name N --repo PATH [--kb-folder F]
  config_add.py ignore --repo PATH
  config_add.py world --name W --collection C

The file is the one resolve_context.py reads ($WORKLOG_CONFIG, else the default
under ~/.config). It is created with its parent dir when missing. Existing
entries are kept. The same entry twice is a no-op that leaves the file
untouched. A repo already declared differently is an error, never a silent
move. A file that cannot be parsed, or has the wrong shape, is never rewritten.
Writes go to a temp file in the same dir, then replace the config in one step.
A symlinked config is written through: the link stays, its target is replaced.
A repo path in a linked git worktree is stored as its main checkout, the path
the resolver matches. Stored paths are compared the same way. When the same
entry is stored under another spelling (a worktree path, or another case on a
case-insensitive disk), it is rewritten to the canonical path, or dropped when
an entry with that path already exists.

Exit codes: 0 written or no change, 1 refused, 2 bad arguments.
"""
import argparse
import functools
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from resolve_context import canonical_repo, config_path, expand, shape_error  # noqa: E402


class Refused(Exception):
    pass


def load(path, yaml):
    if not path.exists():
        return {}
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001 - reported, file left alone
        raise Refused(f"cannot parse {path}, left unchanged: {e}") from e
    data = {} if data is None else data
    error = shape_error(data)
    if error:
        raise Refused(f"{path} is malformed ({error}), left unchanged")
    return data


def write(path, data, yaml):
    # Write through a symlink (dotfiles) so the link survives and its target changes.
    path = Path(os.path.realpath(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            yaml.safe_dump(data, f, sort_keys=False, allow_unicode=True, default_flow_style=False)
            f.flush()
            os.fsync(f.fileno())
        if path.exists():
            os.chmod(tmp, path.stat().st_mode & 0o777)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def declared(data):
    """Yield (world name, project dict, resolved repo path) for every project."""
    for w in data.get("worlds") or []:
        for p in w.get("projects") or []:
            yield w.get("name"), p, canonical(p.get("repo") or "")


def canonical(stored):
    """A stored repo path compared as its main checkout, since older versions stored worktree paths."""
    path = expand(stored)
    if not stored or not path or not path.is_dir() or not needs_mapping(path):
        return path
    try:
        return main_checkout(path)
    except Refused:
        return path


@functools.lru_cache(maxsize=None)
def dir_names(directory):
    """Names in a directory, cached: stored repos often share their parents."""
    return frozenset(os.listdir(directory))


def needs_mapping(path):
    """False when `path` is in its on-disk case and not in a linked worktree, so git can be skipped."""
    try:
        for p in (path, *path.parents):
            if p.name and p.name not in dir_names(p.parent):
                return True  # typed in another case on a case-insensitive disk
        for p in (path, *path.parents):
            if (p / ".git").is_file():
                return True  # linked worktree, or a git dir kept elsewhere
            if (p / ".git").is_dir():
                return False
    except OSError:
        return True
    return False


def ignored_by(data, repo):
    for entry in data.get("ignore") or []:
        i = canonical(entry)
        if i and (i == repo or i in repo.parents):
            return entry
    return None


def add_project(data, world, name, repo, kb_folder):
    same = []
    for w, p, r in declared(data):
        if r != repo:
            continue
        if not (w == world and p.get("name") == name and p.get("kb_folder") == kb_folder):
            raise Refused(f"{repo} is already declared as world {w!r}, project "
                          f"{p.get('name')!r}; ask the operator, nothing changed")
        same.append(p)
    if same:
        # Keep one entry spelled as the canonical path: drop older spellings, or rewrite the only one.
        keep = next((p for p in same if expand(p.get("repo")) == repo), None)
        stale = [p for p in same if p is not keep]
        if not stale:
            return None
        if keep is None:
            keep = stale.pop(0)
            keep["repo"] = str(repo)
        for w in data.get("worlds") or []:
            if w.get("projects"):
                w["projects"] = [p for p in w["projects"] if all(p is not x for x in stale)]
        return f"kept one entry for project {name!r} in world {world!r} at {repo}"
    entry = ignored_by(data, repo)
    if entry:
        raise Refused(f"{repo} is ignored (by {entry!r}); ask the operator, nothing changed")
    project = {"name": name, "repo": str(repo)}
    if kb_folder:
        project["kb_folder"] = kb_folder
    if data.get("worlds") is None:
        data["worlds"] = []
    for w in data["worlds"]:
        if w.get("name") == world:
            if w.get("projects") is None:
                w["projects"] = []
            w["projects"].append(project)
            break
    else:
        data["worlds"].append({"name": world, "projects": [project]})
    return f"added project {name!r} to world {world!r} for {repo}"


def add_ignore(data, repo):
    entries = data.get("ignore") or []
    same = [n for n, entry in enumerate(entries) if canonical(entry) == repo]
    keep = next((n for n in same if expand(entries[n]) == repo), None)
    stale = [n for n in same if n != keep]
    if stale:
        if keep is None:
            keep = stale.pop(0)
            entries[keep] = str(repo)
        data["ignore"] = [e for n, e in enumerate(entries) if n not in stale]
        return f"kept one ignore entry for {repo}"
    if ignored_by(data, repo):
        return None
    for w, p, r in declared(data):
        if r and (r == repo or repo in r.parents):
            raise Refused(f"{r} is declared as world {w!r}, project {p.get('name')!r}; "
                          "ask the operator, nothing changed")
    if data.get("ignore") is None:
        data["ignore"] = []
    data["ignore"].append(str(repo))
    return f"added {repo} to ignore"


def set_world_collection(data, world, collection):
    """Give a world its own Outline collection. A different existing one is never replaced."""
    worlds = data.get("worlds")
    if worlds is None:
        worlds = data["worlds"] = []
    for w in worlds:
        if w.get("name") != world:
            continue
        current = w.get("collection")
        if current == collection:
            return None
        if current:
            raise Refused(f"world {world!r} already uses collection {current!r}; "
                          "ask the operator, nothing changed")
        w["collection"] = collection
        return f"set collection {collection!r} for world {world!r}"
    worlds.append({"name": world, "collection": collection, "projects": []})
    return f"added world {world!r} with collection {collection!r}"


def main_checkout(repo):
    """Map a path in a linked worktree to the same path in the main checkout."""
    try:
        top, main = canonical_repo(repo)
    except OSError:  # no git binary: keep the path as given
        return repo
    if top is None:
        return repo
    # samefile, not string compare: a case-insensitive disk accepts a path typed in another case.
    for ancestor in (repo, *repo.parents):
        if os.path.samefile(ancestor, top):
            return main / repo.relative_to(ancestor)
    raise Refused(f"cannot relate {repo} to its git top level {top}, nothing written")


def segment(value):
    value = value.strip()
    if not value or "/" in value:
        raise argparse.ArgumentTypeError("must be non-empty and contain no '/'")
    return value


def main(argv):
    ap = argparse.ArgumentParser(prog="config-add", description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    pp = sub.add_parser("project", help="declare a repo under a world")
    pp.add_argument("--world", required=True, type=segment)
    pp.add_argument("--name", required=True, type=segment)
    pp.add_argument("--repo", required=True)
    pp.add_argument("--kb-folder")
    ip = sub.add_parser("ignore", help="mark a repo as having no Outline folder")
    ip.add_argument("--repo", required=True)
    wp = sub.add_parser("world", help="give a world its own Outline collection")
    wp.add_argument("--name", required=True, type=segment)
    wp.add_argument("--collection", required=True, type=segment)
    args = ap.parse_args(argv[1:])
    if args.cmd == "world":
        return run(args, None)

    repo = expand(args.repo)
    if not repo or not repo.is_dir():
        print(f"config-add: repo is not a directory: {args.repo}", file=sys.stderr)
        return 2
    try:
        repo = main_checkout(repo)
    except Refused as e:
        print(f"config-add: {e}", file=sys.stderr)
        return 2
    if not repo.is_dir():
        print(f"config-add: {args.repo} maps to {repo} in the main checkout, which is not "
              "a directory; nothing written", file=sys.stderr)
        return 2
    return run(args, repo)


def run(args, repo):
    try:
        import yaml
    except ImportError:
        print("config-add: PyYAML is not installed; nothing written", file=sys.stderr)
        return 1

    path = config_path()
    try:
        data = load(path, yaml)
        if args.cmd == "project":
            message = add_project(data, args.world, args.name, repo, args.kb_folder)
        elif args.cmd == "world":
            message = set_world_collection(data, args.name, args.collection)
        else:
            message = add_ignore(data, repo)
    except Refused as e:
        print(f"config-add: {e}", file=sys.stderr)
        return 1
    if message is None:
        print(f"config-add: no change, {path} already has this entry")
        return 0
    write(path, data, yaml)
    print(f"config-add: {message} in {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
