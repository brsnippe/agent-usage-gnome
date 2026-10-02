#!/usr/bin/python3
# Run with: python3 test/claude-keychain-test.py
#
# Drives the Claude collector's macOS sign-in lookup with a fake `security`
# command: which Keychain entries it asks for, which login wins, and that the
# token never reaches the printed record.

import contextlib
import hashlib
import importlib.machinery
import importlib.util
import io
import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
home = Path(tempfile.mkdtemp(prefix="claude-keychain-test-"))
os.environ["HOME"] = str(home)
os.environ["XDG_CACHE_HOME"] = str(home / "cache")
os.environ["XDG_DATA_HOME"] = str(home / "data")
for name in ("CLAUDE_CONFIG_DIR", "CLAUDE_SECURESTORAGE_CONFIG_DIR"):
  os.environ.pop(name, None)

loader = importlib.machinery.SourceFileLoader("collector", str(ROOT / "agent-usage@local" / "bin" / "agent-usage-claude"))
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


# The fake answers `find-generic-password -s <service> -w` from a JSON file of
# service → secret, exits 44 (security's "not found") otherwise, and logs
# every service it was asked for.
keychain_file = home / "keychain.json"
calls_file = home / "calls.log"
fake = home / "security"
fake.write_text(f"""#!{sys.executable}
import json, sys
args = sys.argv[1:]
service = args[args.index("-s") + 1]
with open({str(calls_file)!r}, "a") as log:
  log.write(service + "\\n")
entries = json.load(open({str(keychain_file)!r}))
if args[0] != "find-generic-password" or "-w" not in args or service not in entries:
  sys.exit(44)
print(entries[service])
""")
fake.chmod(0o755)

claude_dir = home / ".claude"
claude_dir.mkdir()
PLAIN = "Claude Code-credentials"


def hashed(folder):
  return PLAIN + "-" + hashlib.sha256(folder.encode("utf-8")).hexdigest()[:8]


def secret(token, expires_at, tier="default_claude_max_5x", subscription="max"):
  return json.dumps({"claudeAiOauth": {
    "accessToken": token, "refreshToken": "refresh-" + token, "expiresAt": expires_at,
    "rateLimitTier": tier, "subscriptionType": subscription,
  }})


def keychain(entries):
  keychain_file.write_text(json.dumps(entries))
  calls_file.write_text("")


def asked():
  return calls_file.read_text().splitlines()


def credentials_file(text):
  path = claude_dir / ".credentials.json"
  if text is None:
    path.unlink(missing_ok=True)
  else:
    path.write_text(text)


# Linux: no Keychain, the credentials file as before.
collector.SECURITY_TOOL = ""
credentials_file(secret("file-token", 2000))
check("without a Keychain the credentials file is read", collector.oauth_login(claude_dir), ("file-token", 2000, "Max 5x"))
credentials_file(None)
check("without either there is no login", collector.oauth_login(claude_dir), ("", 0, ""))

collector.SECURITY_TOOL = str(fake)
default_hashed = hashed(str(home / ".claude"))

keychain({PLAIN: secret("plain-token", 3000)})
check("macOS: the plain Keychain entry is read", collector.oauth_login(claude_dir), ("plain-token", 3000, "Max 5x"))
check("for the default folder both names are asked for", asked(), [PLAIN, default_hashed])

keychain({PLAIN: secret("stale-token", 1000), default_hashed: secret("live-token", 5000, "", "pro")})
check("an expired plain entry loses to the hashed one", collector.oauth_login(claude_dir), ("live-token", 5000, "Pro"))

keychain({PLAIN: secret("keychain-token", 3000)})
credentials_file(secret("file-token", 9000))
check("a credentials file that lasts longer wins", collector.oauth_login(claude_dir)[0], "file-token")
credentials_file(secret("file-token", 100))
check("a stale credentials file loses to the Keychain", collector.oauth_login(claude_dir)[0], "keychain-token")
credentials_file(None)

keychain({PLAIN: secret("plain-token", 3000).encode("utf-8").hex()})
check("a secret printed as hex is decoded", collector.oauth_login(claude_dir)[0], "plain-token")

keychain({PLAIN: "not json", default_hashed: json.dumps({"other": {}})})
check("entries that hold no Claude login are ignored", collector.oauth_login(claude_dir), ("", 0, ""))

keychain({})
check("no entries: no login", collector.oauth_login(claude_dir), ("", 0, ""))

work = str(home / ".claude-work")
os.environ["CLAUDE_CONFIG_DIR"] = work
keychain({PLAIN: secret("default-account", 9000), hashed(work): secret("work-account", 3000)})
check("CLAUDE_CONFIG_DIR: only that folder's entry", (collector.oauth_login(claude_dir)[0], asked()), ("work-account", [hashed(work)]))

os.environ["CLAUDE_SECURESTORAGE_CONFIG_DIR"] = ""
keychain({PLAIN: secret("plain-token", 3000)})
check("an empty CLAUDE_SECURESTORAGE_CONFIG_DIR means the plain name, and only that one",
      (collector.oauth_login(claude_dir)[0], asked()), ("plain-token", [PLAIN]))

storage = str(home / "storage")
os.environ["CLAUDE_SECURESTORAGE_CONFIG_DIR"] = storage
keychain({hashed(storage): secret("storage-token", 3000)})
check("a set CLAUDE_SECURESTORAGE_CONFIG_DIR picks its own entry", (collector.oauth_login(claude_dir)[0], asked()), ("storage-token", [hashed(storage)]))
del os.environ["CLAUDE_CONFIG_DIR"], os.environ["CLAUDE_SECURESTORAGE_CONFIG_DIR"]

collector.SECURITY_TOOL = str(home / "missing-security")
keychain({})
check("a missing security command is no login, not a crash", collector.oauth_login(claude_dir), ("", 0, ""))
collector.SECURITY_TOOL = str(fake)

# The whole collector: the Keychain token goes to the limits request and
# nowhere else.
probed = []
collector.probe_limits = lambda token: probed.append(token) or {
  "ok": True, "limits": [{"label": "Session (5-hour)", "percent": 0.4, "resetsAt": "2099-01-01T00:00:00+00:00"}],
}
keychain({PLAIN: secret("sk-ant-oat01-secret", 99_999_999_999_999)})
sys.argv = ["agent-usage-claude", "--force"]
out = io.StringIO()
with contextlib.redirect_stdout(out):
  collector.main()
record = json.loads(out.getvalue())
check("the limits request gets the Keychain token", probed, ["sk-ant-oat01-secret"])
check("the record has the limits and the plan", (record["limits"][0]["percent"], record["tierLabel"]), (0.4, "Max 5x"))
check("the token and refresh token are not in the record", "secret" in out.getvalue(), False)

print("\nall passed" if failures == 0 else f"\n{failures} failed")
sys.exit(1 if failures else 0)
