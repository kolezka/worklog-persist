"""The DSH adapter runs on the published claude-plugin-dsh package, installed in dsh/.

Each test copies the plugin into a temp dir (no node_modules, no .git), so it proves
a standalone install works without this checkout's own dsh/node_modules.
"""
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = "claude-plugin-dsh"
VERSION = "0.2.0"
INTEGRITY = "sha512-pzSobglwIh7NuG5Y5W331kVIg5NExU5wnzW3citMKXl57CMmVW255b5zPLDyVA/ERSgUjhrsugBgkEq5p+S1Zw=="

# Resolves the runtime from the adapter's own directory, then drives the adapter
# through a fake Cordis context and prints what it registered.
PROBE = r"""
import { createRequire } from 'node:module'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'

const dsh = process.argv[1]
const out = { resolved: null, version: null, error: null }
try {
  const require = createRequire(join(dsh, 'index.js'))
  out.resolved = require.resolve('claude-plugin-dsh')
  out.version = JSON.parse(readFileSync(require.resolve('claude-plugin-dsh/package.json'), 'utf8')).version
} catch (error) {
  out.error = error.code ?? String(error)
  console.log(JSON.stringify(out))
  process.exit(0)
}
const { apply, name } = await import(pathToFileURL(join(dsh, 'index.js')).href)
out.name = name
out.commands = {}
out.skills = {}
out.events = []
const providers = []
const ctx = {
  logger: { warn: (message) => { throw new Error(message) } },
  skills: { registerProvider: (create) => providers.push(create({ signal: new AbortController().signal, invalidate() {} })) },
  commands: { register: (command) => {
    let text = null
    command.handler({ rawInput: '', agent: { followup: (message) => { text = message.content[0].text } } })
    out.commands[command.name] = text
  } },
  systemPrompt: { section() {} },
  workingDirectory: { get: () => process.cwd() },
  inject: (_services, callback) => callback(ctx),
  effect() {},
  on: (event) => out.events.push(event),
}
await apply(ctx, {})
for (const provider of providers) {
  for (const candidate of await provider.list({})) {
    out.skills[candidate.name] = (await provider.get(candidate, {}))?.content ?? null
  }
}
console.log(JSON.stringify(out))
"""


def _copy_plugin(dest: Path) -> Path:
    shutil.copytree(ROOT, dest, ignore=shutil.ignore_patterns(".git", "node_modules", ".venv", "__pycache__", ".pytest_cache"))
    return dest / "dsh"


def _bun_install(dsh: Path) -> None:
    result = subprocess.run(["bun", "install", "--frozen-lockfile"], cwd=dsh, capture_output=True, text=True)
    assert result.returncode == 0, f"bun install failed:\n{result.stdout}\n{result.stderr}"


def _probe(dsh: Path) -> dict:
    # Run from outside the plugin so nothing but the adapter's own dir can resolve the runtime.
    env = {k: v for k, v in os.environ.items() if k != "NODE_PATH"}
    result = subprocess.run(
        ["node", "--input-type=module", "-e", PROBE, str(dsh)],
        cwd=dsh.parents[1], capture_output=True, text=True, env=env,
    )
    assert result.returncode == 0, f"probe crashed:\n{result.stderr}"
    return json.loads(result.stdout)


def _assert_installed_runtime(seen: dict, dsh: Path) -> None:
    installed = (dsh / "node_modules" / RUNTIME).resolve()
    resolved = Path(seen["resolved"]).resolve() if seen["resolved"] else None
    assert resolved is not None and resolved.is_relative_to(installed), (
        f"{RUNTIME} did not resolve from {installed}: resolved={seen['resolved']} error={seen['error']}"
    )
    assert seen["version"] == VERSION


@pytest.fixture(scope="module")
def installed(tmp_path_factory) -> tuple[Path, dict]:
    dsh = _copy_plugin(tmp_path_factory.mktemp("standalone") / "worklog-persist")
    _bun_install(dsh)
    return dsh, _probe(dsh)


def test_dependency_contract_is_exact_and_not_vendored():
    package = json.loads((ROOT / "dsh/package.json").read_text())
    assert package["dependencies"] == {RUNTIME: VERSION}
    assert "bun.lock" in package["files"]
    assert not any("claude-compat" in entry for entry in package["files"])
    assert not (ROOT / "dsh/claude-compat.js").exists()
    source = (ROOT / "dsh/index.js").read_text()
    assert "import { createPlugin, rootFrom } from 'claude-plugin-dsh'" in source
    assert "rootFrom(import.meta.url)" in source
    lock = (ROOT / "dsh/bun.lock").read_text()
    assert f'"{RUNTIME}@{VERSION}"' in lock and INTEGRITY in lock


def test_runtime_resolves_from_the_adapters_own_install(installed):
    dsh, seen = installed
    _assert_installed_runtime(seen, dsh)


def test_adapter_registers_skill_commands_and_hooks_with_real_bodies(installed):
    dsh, seen = installed
    _assert_installed_runtime(seen, dsh)
    assert seen["name"] == "claude-compat-worklog-persist"
    expected = ["checkpoint", "complete", "dry-run", "handoff", "load", "off", "search", "setup", "start"]
    assert sorted(seen["commands"]) == [f"wl-{stem}" for stem in expected]
    for stem in expected:
        text = seen["commands"][f"wl-{stem}"]
        assert text.startswith(f"<command-name>/worklog-persist:{stem}</command-name>"), text[:120]
    # `show` is the Claude Code-only native panel, so it stays excluded.
    assert "wl-show" not in seen["commands"]
    for stem in expected:
        source = (ROOT / f"commands/{stem}.md").read_text().split("\n---\n", 1)[-1].strip()
        assert source.splitlines()[0] in seen["commands"][f"wl-{stem}"], stem
    assert list(seen["skills"]) == ["worklog-persist"]
    skill_body = (ROOT / "skills/worklog-persist/SKILL.md").read_text().split("\n---\n", 1)[1].strip()
    assert skill_body.splitlines()[0] in seen["skills"]["worklog-persist"]
    # hooks.json declares SessionStart and Stop; disposal cleans up per-agent state.
    assert set(seen["events"]) == {"agent/created", "agent/turn-stopping", "agent/disposed"}


def test_check_rejects_an_adapter_without_its_dependency(tmp_path):
    # Negative control: the same copy minus `bun install` must fail at the resolution check.
    dsh = _copy_plugin(tmp_path / "worklog-persist")
    seen = _probe(dsh)
    assert seen["resolved"] is None and seen["error"] == "MODULE_NOT_FOUND"
    with pytest.raises(AssertionError, match="did not resolve from"):
        _assert_installed_runtime(seen, dsh)
