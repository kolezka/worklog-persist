#!/usr/bin/env python3
"""Stop hook for worklog-persist.

Reads the Claude Code Stop-hook JSON on stdin (`session_id`, `transcript_path`,
`cwd`, `stop_hook_active`). When work has shipped since the last Outline write in
this transcript, prints `{"decision":"block","reason":...}` so
the model gets one more forced turn to persist state via the worklog-persist
skill. Otherwise prints nothing. Always exits 0: this hook must never crash a
session or turn an internal error into a stuck stop.

Every block costs the user a turn, so the bar is high: only a Bash command that
ships work counts (`SHIP_RE`: git commit or push, gh pr create or merge, a
release, publish or deploy). Edits and long runs of tool calls never block on
their own. The hook stays quiet for `WORKLOG_STOP_COOLDOWN_MIN` minutes after a block
or an Outline write, and never blocks a session nobody is watching (`claude -p`,
SDK runs).

Stop fires at the end of every turn, so a decline ("trivial, stopping") must not
be re-blocked forever: each block records the id of the last tool_use it saw, in a
per-session marker file, and later stops only look at tool_uses after that id (or
after the last Outline write, whichever is later). If the marker id is no longer
found in the transcript, it is treated as absent and the hook falls back to the
last write, as if there were no marker at all. A block that cannot be recorded
(no `session_id`, no tool_use id, an unwritable state dir) would repeat on every
turn, so the hook allows the stop instead.

The transcript is evaluated first, with no subprocess call. `resolve-context.sh`
only runs once the hook has already decided to block, since it is the one part of
this hook slow and fallible enough (plugin config YAML, subprocess) to be worth not
paying for on every silent turn. If it fails, the hook still blocks, just with a
reason that carries no world context.

Usage: stop_guard.py < stop-hook-input.json
"""
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
WRITE_RE = re.compile(r"^mcp__.*outline.*__(create_document|update_document)$")
# A command that ships work. git commit/push behind any number of `-C <dir>` /
# `-c key=value` options (`\b...\b(?!-)` so `commit` skips `commit-tree`), a PR
# opened or merged, a release, a package publish, or a deploy.
_GIT_OPT = r"(?:-C\s+\S+|-c\s+\S+=\S+)"
SHIP_RE = re.compile(
    rf"\bgit\b(?:\s+{_GIT_OPT})*\s+(?:commit|push)\b(?!-)"
    r"|\bgh\s+pr\s+(?:create|merge)\b"
    r"|\bgh\s+release\s+create\b"
    r"|\b(?:npm|pnpm|yarn|cargo|uv|poetry|gem)\s+publish\b"
    r"|\btwine\s+upload\b"
    r"|\bmake\s+(?:release|deploy)\b"
    r"|\b(?:vercel|netlify|fly|flyctl|firebase|wrangler|railway|serverless|sls)\s+deploy\b"
    r"|(?:^|[\s;&|/])(?:release|deploy)\.sh\b"
)
DEFAULT_COOLDOWN_MIN = 90
# Claude Code's CLAUDE_CODE_ENTRYPOINT for `claude -p` and the Agent SDKs.
UNATTENDED_ENTRYPOINTS = {"sdk-cli", "sdk-ts", "sdk-py"}
SESSION_ID_BAD_CHARS_RE = re.compile(r"[^A-Za-z0-9_-]")


def persistence_is_off():
    r = subprocess.run(
        ["bash", str(HERE / "persistence-state.sh"), "status"],
        capture_output=True, text=True, timeout=10,
    )
    return r.stdout.strip() == "off"


def resolve_context(cwd):
    r = subprocess.run(
        ["bash", str(HERE / "resolve-context.sh")],
        cwd=cwd, capture_output=True, text=True, timeout=10,
    )
    return json.loads(r.stdout)


def env_int(name, default):
    try:
        return int(os.environ.get(name) or default)
    except ValueError:
        return default


def is_unattended():
    """True when no human watches this session, so a forced turn helps nobody.

    Claude Code puts CLAUDE_CODE_SESSION_ATTENDED ("0" or "1") in each hook's
    environment. Without it, fall back to the entrypoint. With neither, assume a
    human is there.
    """
    attended = os.environ.get("CLAUDE_CODE_SESSION_ATTENDED")
    if attended in ("0", "1"):
        return attended == "0"
    return os.environ.get("CLAUDE_CODE_ENTRYPOINT") in UNATTENDED_ENTRYPOINTS


def load_tool_uses(transcript_path):
    """Ordered (name, input, id, timestamp) for every non-sidechain assistant tool_use.

    Unparsable lines are skipped, never fatal: a transcript is append-only JSONL
    that may contain a partial last line.
    """
    tool_uses = []
    with open(transcript_path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if not isinstance(rec, dict) or rec.get("isSidechain") is True:
                continue
            if rec.get("type") != "assistant":
                continue
            content = (rec.get("message") or {}).get("content")
            if not isinstance(content, list):
                continue
            for item in content:
                if isinstance(item, dict) and item.get("type") == "tool_use":
                    tool_uses.append((item.get("name") or "", item.get("input") or {},
                                      item.get("id"), rec.get("timestamp")))
    return tool_uses


def last_write_index(tool_uses):
    """Index of the last Outline write tool_use, or -1 if there was none."""
    last = -1
    for idx, (name, _input, _id, _ts) in enumerate(tool_uses):
        if WRITE_RE.match(name):
            last = idx
    return last


def marker_index(tool_uses, marker_id):
    """Index of the tool_use whose id matches the marker, or None if not found."""
    if marker_id is None:
        return None
    for idx, (_name, _input, tid, _ts) in enumerate(tool_uses):
        if tid == marker_id:
            return idx
    return None


def state_stop_dir():
    base = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local/state")
    return Path(base) / "worklog-persist" / "stop"


def marker_path(session_id):
    """Path recording the last tool_use id this session was already blocked for.

    None when `session_id` is missing or empty, or sanitizes to nothing: the
    marker feature is skipped rather than guessing at a shared file.
    """
    if not isinstance(session_id, str) or not session_id:
        return None
    sid = SESSION_ID_BAD_CHARS_RE.sub("", session_id)
    return state_stop_dir() / sid if sid else None


def read_marker(session_id):
    """The last tool_use id already shown for this session. None on any failure."""
    path = marker_path(session_id)
    if not path:
        return None
    try:
        raw = path.read_text().strip()
    except OSError:
        return None
    return raw or None


def write_marker(session_id, tool_use_id):
    """Record the last tool_use id shown. False when it could not be recorded.

    The file's mtime doubles as the time of the last block.
    """
    path = marker_path(session_id)
    if not path or tool_use_id is None:
        return False
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(str(tool_use_id))
    except OSError:
        return False
    return True


def last_block_time(session_id):
    """Epoch seconds of this session's last block, or None."""
    path = marker_path(session_id)
    if not path:
        return None
    try:
        return path.stat().st_mtime
    except OSError:
        return None


def parse_timestamp(value):
    """Epoch seconds for a transcript record's ISO timestamp, or None."""
    if not isinstance(value, str):
        return None
    try:
        # fromisoformat only accepts a trailing "Z" from Python 3.11.
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def has_shipped(subset):
    """True when a Bash tool_use in `subset` ran a command matching SHIP_RE."""
    for name, tool_input, _id, _ts in subset:
        if name == "Bash":
            command = tool_input.get("command")
            if isinstance(command, str) and SHIP_RE.search(command):
                return True
    return False


def build_reason(identity):
    lead = ("Work was committed, pushed or shipped since the last Outline write. Run the "
            "worklog-persist skill: checkpoint for ongoing work, handoff if the "
            "session is ending or blocked, or complete if the task is done.")
    trivial = "If the work was trivial and not worth a record, say so in one line and stop."
    if identity is None:
        where = "Context could not be resolved here; the skill resolves the path itself."
        return " ".join([lead, where, trivial])
    world = identity.get("world") or "UNRESOLVED"
    if world == "UNRESOLVED":
        where = ("World is unresolved for this project. Run the onboarding flow "
                 "(/setup) before writing anything.")
    else:
        where = (f"Resolved context: world `{world}`, "
                 f"project `{identity.get('project')}`, "
                 f"tasks path `{identity.get('tasks_path')}`.")
        if identity.get("world_source") == "path-root":
            where += (" (world inferred from the directory; if that is wrong, "
                      "run /setup to declare the repo)")
    return " ".join([lead, where, trivial])


def run(data):
    if data.get("stop_hook_active"):
        return None
    if is_unattended():
        return None
    if persistence_is_off():
        return None

    transcript_path = data.get("transcript_path")
    if not transcript_path or not os.path.isfile(transcript_path):
        return None

    cooldown_sec = env_int("WORKLOG_STOP_COOLDOWN_MIN", DEFAULT_COOLDOWN_MIN) * 60

    tool_uses = load_tool_uses(transcript_path)
    session_id = data.get("session_id")
    found = marker_index(tool_uses, read_marker(session_id))
    last_write = last_write_index(tool_uses)
    start = max((found + 1) if found is not None else 0, last_write + 1)
    subset = tool_uses[start:]
    if not has_shipped(subset):
        return None

    # Skipped work is not lost: the marker stays put, so it counts at the next stop.
    write_time = parse_timestamp(tool_uses[last_write][3]) if last_write >= 0 else None
    now = time.time()
    # A time ahead of the clock would mute the guard until long after it; ignore it.
    recent = [t for t in (last_block_time(session_id), write_time) if t is not None and t <= now]
    if recent and now - max(recent) < cooldown_sec:
        return None

    # Only reached when about to block: resolve-context is the slow, fallible part
    # (plugin config YAML, a subprocess), not worth paying for on every silent turn.
    try:
        identity = resolve_context(data.get("cwd") or ".")
    except Exception:  # noqa: BLE001 - a failed lookup still blocks, just generically
        identity = None
    if identity and identity.get("ignored"):
        return None

    if not write_marker(session_id, tool_uses[-1][2]):
        return None
    return {"decision": "block", "reason": build_reason(identity)}


def main():
    try:
        data = json.load(sys.stdin)
        result = run(data)
    except Exception:  # noqa: BLE001 - any internal error must allow the stop
        return 0
    if result:
        print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
