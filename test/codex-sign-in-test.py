#!/usr/bin/python3
# Run with: python3 test/codex-sign-in-test.py
#
# Drives the Codex collector's limits check with a fake `codex app-server`:
# signed out it says so (with `codex login` as the fix), signed in it reads
# the plan and the limits.

import importlib.machinery
import importlib.util
import os
import stat
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
home = Path(tempfile.mkdtemp(prefix="codex-sign-in-test-"))
os.environ["HOME"] = str(home)
os.environ["XDG_CACHE_HOME"] = str(home / "cache")
os.environ["XDG_DATA_HOME"] = str(home / "data")

loader = importlib.machinery.SourceFileLoader("collector", str(ROOT / "agent-usage@local" / "bin" / "agent-usage-codex"))
spec = importlib.util.spec_from_loader("collector", loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

failures = 0


def check(name, actual, expected):
  global failures
  ok = actual == expected
  if not ok:
    failures += 1
  print(("ok   " if ok else "FAIL ") + name + ("" if ok else f"\n     got      {actual!r}\n     expected {expected!r}"))


# Answers the way codex 0.159's app server does, signed in or not.
FAKE = """#!%s
import json, os, sys
signed_in = os.environ.get("FAKE_CODEX_SIGNED_IN") == "1"
for line in sys.stdin:
  message = json.loads(line)
  if "id" not in message:
    continue
  method = message["method"]
  if method == "initialize":
    result = {"userAgent": "fake"}
  elif method == "account/read":
    account = {"type": "chatgpt", "planType": "plus"} if signed_in else None
    result = {"account": account, "requiresOpenaiAuth": True}
  elif method == "account/rateLimits/read" and signed_in:
    result = {"rateLimits": {"planType": "plus", "primary": {"usedPercent": 42, "windowDurationMins": 300, "resetsAt": 1790000000}}}
  else:
    error = {"code": -32600, "message": "codex account authentication required to read rate limits"}
    print(json.dumps({"id": message["id"], "error": error}), flush=True)
    continue
  print(json.dumps({"id": message["id"], "result": result}), flush=True)
""" % sys.executable

codex = home / "codex"
codex.write_text(FAKE)
codex.chmod(codex.stat().st_mode | stat.S_IXUSR)
collector.find_command = lambda name: str(codex) if name == "codex" else None

# The collector starts codex with the environment it captured at import.
collector.ENV["FAKE_CODEX_SIGNED_IN"] = "0"
signed_out = collector.fetch_codex_rpc()
check("signed out says so, with the fix",
      (signed_out["usageStatusText"], signed_out["authHelpText"], signed_out["limits"]),
      ("Not signed in", "Run `codex login` to authenticate.", []))

collector.ENV["FAKE_CODEX_SIGNED_IN"] = "1"
signed_in = collector.fetch_codex_rpc()
check("signed in reads the plan and the limits, with no problem",
      (signed_in["usageStatusText"], signed_in["tierLabel"], [(entry["label"], entry["percent"]) for entry in signed_in["limits"]]),
      ("", "plus", [("5h window", 0.42)]))

collector.find_command = lambda name: None
check("no codex at all is a different problem", collector.fetch_codex_rpc()["usageStatusText"], "Codex unavailable")

print("\nall passed" if failures == 0 else f"\n{failures} failed")
sys.exit(1 if failures else 0)
