#!/usr/bin/python3
# Run with: python3 test/session-hooks-test.py
#
# agent-usage-session in a throwaway home: Claude Code's hook events and the
# session files they leave, and adding and removing the hooks in Claude Code's
# settings and the plugin in OpenCode's config, next to other people's.

import importlib.machinery
import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "agent-usage@local" / "hooks" / "agent-usage-session"
home = Path(tempfile.mkdtemp(prefix="session-hooks-test-"))
bin_dir = home / "fake-bin"
bin_dir.mkdir()
os.environ.update({
  "HOME": str(home),
  "XDG_STATE_HOME": str(home / ".local" / "state"),
  "XDG_CONFIG_HOME": str(home / ".config"),
  "PATH": f"{bin_dir}:/usr/bin:/bin",
})
os.environ.pop("CLAUDE_CONFIG_DIR", None)

loader = importlib.machinery.SourceFileLoader("sessions", str(SCRIPT))
spec = importlib.util.spec_from_loader("sessions", loader)
hooks = importlib.util.module_from_spec(spec)
loader.exec_module(hooks)
# Only the fake opencode below, never one installed on this machine.
hooks.OPENCODE_DIRS = []

failures = 0


def check(name, actual, expected):
  global failures
  ok = actual == expected
  if not ok:
    failures += 1
  print(("ok   " if ok else "FAIL ") + name + ("" if ok else f"\n     got      {actual!r}\n     expected {expected!r}"))


SESSIONS = home / ".local" / "state" / "omarchy" / "agents" / "sessions"
FILE = SESSIONS / "claude-abc.json"


def event(name, **extra):
  hooks.hook_claude({"hook_event_name": name, "session_id": "abc", "cwd": "/work/project", **extra})


def record():
  return json.loads(FILE.read_text()) if FILE.exists() else None


def state():
  current = record()
  return current and (current["state"], current.get("waitingFor"))


# ---- Claude Code's events
stale = SESSIONS / "claude-old.json"
SESSIONS.mkdir(parents=True)
stale.write_text(json.dumps({"agent": "claude", "session": "old", "state": "waiting", "updated": hooks.now_ms(), "pid": 2 ** 22 + 12345}))
event("SessionStart", source="startup")
check("a new session is idle", state(), ("idle", None))
check("with a running pid and the folder", [hooks.pid_alive(record()["pid"]), record()["cwd"]], [True, "/work/project"])
check("starting a session clears out the files of agents that are gone", stale.exists(), False)

event("UserPromptSubmit", prompt="hi")
check("a prompt makes it work", state(), ("working", None))
working_since = record()["since"]
event("PreToolUse", tool_name="Bash")
check("other tools change nothing", record()["since"], working_since)
event("PreToolUse", tool_name="AskUserQuestion")
check("a question waits for you", state(), ("waiting", ""))
event("PostToolUse", tool_name="Bash", agent_id="sub-1")
check("a subagent's tool doesn't end the main agent's wait", state(), ("waiting", ""))
event("PostToolUse", tool_name="AskUserQuestion")
check("the answer ends it", state(), ("working", None))

event("PermissionRequest", tool_name="Bash", agent_id="sub-1")
check("a subagent's permission prompt waits for you too", state(), ("waiting", "sub-1"))
event("PostToolUse", tool_name="Read")
check("the main agent's tools don't end the subagent's wait", state(), ("waiting", "sub-1"))
event("PostToolUseFailure", tool_name="Bash", agent_id="sub-1")
check("the subagent's own tool does, failed or not", state(), ("working", None))
event("Elicitation", mcp_server_name="db")
event("ElicitationResult", mcp_server_name="db")
check("an MCP server asking, and the answer", state(), ("working", None))
event("PreToolUse", tool_name="ExitPlanMode")
check("a plan waiting for approval", state(), ("waiting", ""))

event("Stop")
check("a finished turn is ready", state(), ("ready", None))
ready_since = record()["since"]
event("PostToolUse", tool_name="Bash")
event("StopFailure", error="rate_limit")
check("staying ready keeps when it got there", [state(), record()["since"]], [("ready", None), ready_since])
event("SessionEnd", reason="prompt_input_exit")
check("the end of the session removes its file", FILE.exists(), False)
event("PostToolUse", tool_name="Bash")
check("and tool events after it don't bring it back", FILE.exists(), False)
hooks.hook_claude({"hook_event_name": "Stop"})
check("an event without a session is ignored", sorted(p.name for p in SESSIONS.glob("*.json")), [])

run = subprocess.run([sys.executable, str(SCRIPT), "hook", "claude"], input=json.dumps(
  {"hook_event_name": "UserPromptSubmit", "session_id": "../../evil", "cwd": "/w"}), capture_output=True, text=True)
check("from Claude Code: the event on stdin", [run.returncode, run.stdout, run.stderr], [0, "", ""])
check("a session id can't leave the folder", sorted(p.name for p in SESSIONS.glob("*.json")), ["claude-.._.._evil.json"])
check("the pid is Claude Code's, not the shell's or the script's", json.loads((SESSIONS / "claude-.._.._evil.json").read_text())["pid"], os.getpid())
run = subprocess.run([sys.executable, str(SCRIPT), "hook", "claude"], input="not json", capture_output=True, text=True)
check("bad input fails quietly", [run.returncode, run.stderr], [0, ""])

# ---- Claude Code's settings
claude = home / ".claude"
settings = claude / "settings.json"
check("no Claude Code, no hooks", hooks.edit_claude_settings(install=True), "Claude Code: not set up here (no ~/.claude), skipped.")
check("and no settings file made", claude.exists(), False)

claude.mkdir()
theirs = {
  "theme": "dark",
  "hooks": {
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "/home/me/block-rm.sh"}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "notify-send done"}]}],
  },
}
settings.write_text(json.dumps(theirs, indent=4))
settings.chmod(0o600)
link = home / ".local" / "bin" / "agent-usage-session"

out = subprocess.run([sys.executable, str(SCRIPT), "install"], capture_output=True, text=True)
installed = json.loads(settings.read_text())
check("install says what it did", out.stdout.splitlines(), [
  "  Claude Code: added the session hooks to ~/.claude/settings.json.",
  "  OpenCode: not installed here, skipped.",
])
check("it links the script where the hooks find it", os.path.realpath(link), str(SCRIPT))
command = f"{sys.executable} {link} hook claude"
check("every event gets a hook", sorted(installed["hooks"]), sorted([
  "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "Elicitation", "PostToolUse",
  "PostToolUseFailure", "ElicitationResult", "Stop", "StopFailure", "SessionEnd"]))
check("theirs come first and stay as they were", [installed["theme"], installed["hooks"]["PreToolUse"][0], installed["hooks"]["Stop"][0]],
      [theirs["theme"], theirs["hooks"]["PreToolUse"][0], theirs["hooks"]["Stop"][0]])
check("the question tools only", installed["hooks"]["PreToolUse"][1],
      {"matcher": "AskUserQuestion|ExitPlanMode", "hooks": [{"type": "command", "command": command, "timeout": 10}]})
check("the tool hooks run in the background", installed["hooks"]["PostToolUse"],
      [{"hooks": [{"type": "command", "command": command, "timeout": 10, "async": True}]}])
check("the turn's edges don't", installed["hooks"]["Stop"][1], {"hooks": [{"type": "command", "command": command, "timeout": 10}]})
check("the settings file stays private", stat.S_IMODE(settings.stat().st_mode), 0o600)

before = settings.stat().st_mtime_ns
check("installing again changes nothing", hooks.edit_claude_settings(install=True),
      "Claude Code: the session hooks are already in ~/.claude/settings.json.")
check("and writes nothing", settings.stat().st_mtime_ns, before)
check("status sees them", hooks.claude_status(), "hooks in ~/.claude/settings.json for 11 of 11 events")

out = subprocess.run([sys.executable, str(SCRIPT), "uninstall"], capture_output=True, text=True)
check("uninstall says what it did", out.stdout.splitlines(), ["  Claude Code: took the session hooks out of ~/.claude/settings.json."])
check("and leaves theirs exactly as they were", json.loads(settings.read_text()), theirs)
check("and removes the link", link.is_symlink(), False)
check("uninstalling again does nothing", hooks.edit_claude_settings(install=False), "")

settings.write_text(json.dumps({"model": "opus"}))
hooks.edit_claude_settings(install=True)
hooks.edit_claude_settings(install=False)
check("settings that had no hooks get none back", json.loads(settings.read_text()), {"model": "opus"})

settings.write_text("{ not json")
check("broken settings are left alone", [hooks.edit_claude_settings(install=True), settings.read_text()],
      ["Claude Code: ~/.claude/settings.json isn't valid JSON, so it's left alone.", "{ not json"])

dotfiles = home / "dotfiles"
dotfiles.mkdir()
(dotfiles / "claude-settings.json").write_text("{}")
settings.unlink()
settings.symlink_to(dotfiles / "claude-settings.json")
hooks.edit_claude_settings(install=True)
check("a settings file linked from elsewhere stays a link", [settings.is_symlink(), "hooks" in json.loads((dotfiles / "claude-settings.json").read_text())], [True, True])

os.environ["CLAUDE_CONFIG_DIR"] = str(home / "work-claude")
(home / "work-claude").mkdir()
hooks.edit_claude_settings(install=True)
check("CLAUDE_CONFIG_DIR is where Claude Code's settings are", (home / "work-claude" / "settings.json").exists(), True)
os.environ.pop("CLAUDE_CONFIG_DIR")

# ---- OpenCode's plugin
plugin = home / ".config" / "opencode" / "plugins" / "agent-usage.js"


def fake_opencode(version):
  path = bin_dir / "opencode"
  path.write_text(f"#!/bin/sh\necho 'opencode v{version}'\n")
  path.chmod(0o755)


check("no OpenCode, no plugin", [hooks.install_opencode_plugin(), plugin.exists()], ["OpenCode: not installed here, skipped.", False])
fake_opencode("1.18.33")
check("OpenCode 1 loads plugins differently, so it gets none", [hooks.install_opencode_plugin(), plugin.exists()],
      ["OpenCode: version 1.18.33 is installed; the session colors need OpenCode 2, skipped.", False])
fake_opencode("2.0.22")
check("OpenCode 2 gets the plugin", hooks.install_opencode_plugin(), "OpenCode: added the session plugin to ~/.config/opencode/plugins/agent-usage.js.")
check("a copy of it", plugin.read_text(), (SCRIPT.parent / "opencode-agent-usage.js").read_text())
check("installing again leaves it", hooks.install_opencode_plugin(), "OpenCode: the plugin is already in ~/.config/opencode/plugins/agent-usage.js.")
plugin.write_text("// agent-usage.sessions, an older version\n")
check("an older version is replaced", [hooks.install_opencode_plugin(), plugin.read_text() == (SCRIPT.parent / "opencode-agent-usage.js").read_text()],
      ["OpenCode: added the session plugin to ~/.config/opencode/plugins/agent-usage.js.", True])
check("status sees it", hooks.opencode_status(), "plugin in ~/.config/opencode/plugins/agent-usage.js (current; OpenCode 2.0.22)")
check("uninstall removes it", [hooks.remove_opencode_plugin(), plugin.exists()],
      ["OpenCode: removed the session plugin from ~/.config/opencode/plugins/agent-usage.js.", False])
plugin.write_text("export default {id: 'someone-else'}\n")
check("someone else's file there is left alone", [hooks.install_opencode_plugin(), hooks.remove_opencode_plugin(), plugin.exists()],
      ["OpenCode: ~/.config/opencode/plugins/agent-usage.js is someone else's file, so it's left alone.", "", True])

out = subprocess.run([sys.executable, str(SCRIPT), "status"], capture_output=True, text=True)
check("status runs", [out.returncode, out.stdout.splitlines()[0].split(":")[0]], [0, "claude"])
out = subprocess.run([sys.executable, str(SCRIPT), "install", "--quiet"], capture_output=True, text=True)
check("--quiet says nothing", [out.returncode, out.stdout, out.stderr], [0, "", ""])
out = subprocess.run([sys.executable, str(SCRIPT)], capture_output=True, text=True)
check("without a command it shows how to use it", [out.returncode, out.stderr.split()[0]], [2, "agent-usage-session"])

subprocess.run(["rm", "-rf", str(home)])
print("\nall passed" if failures == 0 else f"\n{failures} failed")
sys.exit(1 if failures else 0)
