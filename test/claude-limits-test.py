#!/usr/bin/python3
# Run with: python3 test/claude-limits-test.py
#
# Drives the Claude collector's limits logic with a fake clock and a fake
# Anthropic endpoint: stale marking, the 429 backoff, and recovery.

import importlib.machinery
import importlib.util
import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
cache = tempfile.mkdtemp(prefix="claude-limits-test-")
os.environ["XDG_CACHE_HOME"] = cache

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


class Clock:
  now = 1_790_000_000.0

  def time(self):
    return self.now


clock = Clock()
collector.time = clock

LIMITS = [{"label": "Session (5-hour)", "percent": 0.3, "resetsAt": "2099-01-01T00:00:00+00:00"}]
calls = []
answers = []


def fake_probe(token):
  calls.append(clock.now)
  return answers.pop(0)


real_probe = collector.probe_limits
collector.probe_limits = fake_probe
TOKEN, NEVER_EXPIRES = "token", 0


def run(force=False):
  return collector.collect_limits(TOKEN, NEVER_EXPIRES, force)


def cache_file():
  return json.loads((Path(cache) / "omarchy" / "agent-usage" / "claude-limits.json").read_text())


ok = {"ok": True, "limits": LIMITS}
too_many = {"ok": False, "helpText": "rate limited", "rateLimited": True, "retryAfter": 0}

answers.append(ok)
result = run()
check("a good answer is fresh and timestamped", (result["limits"], result.get("limitsStale"), result["limitsFetchedAt"]),
      (LIMITS, None, collector.iso_from_ms(round(clock.now * 1000))))
first_fetch = result["limitsFetchedAt"]

clock.now += 5
result = run()
check("within 15 s the cached answer is reused, not probed", (len(calls), result.get("limitsStale")), (1, None))

clock.now += 20
answers.append(too_many)
result = run()
check("a 429 keeps the last numbers but marks them stale",
      (result["limits"], result["limitsStale"], result["limitsFetchedAt"]), (LIMITS, True, first_fetch))
check("and says when it will try again", result["limitsNote"].startswith("Anthropic is rate limiting checks · next try "), True)
check("first backoff is 60 s (retry-after 0 gives no advice)", cache_file()["backoffSeconds"], 60)
check("the cache still holds the last good reading", (cache_file()["limits"], cache_file()["fetchedAtMs"]),
      (LIMITS, round((clock.now - 25) * 1000)))

clock.now += 30
result = run(force=True)
check("during the backoff even a forced refresh does not probe", (len(calls), result["limitsStale"]), (2, True))

clock.now += 31
answers.append(too_many)
run()
check("a second refusal doubles the wait", cache_file()["backoffSeconds"], 120)

clock.now += 121
answers.append(dict(too_many, retryAfter=600))
run()
check("a longer retry-after from Anthropic wins", cache_file()["backoffSeconds"], 600)

clock.now += 601
answers.append(too_many)
run()
check("the wait is capped at 15 minutes", cache_file()["backoffSeconds"], 900)

clock.now += 901
answers.append(ok)
result = run()
check("the next good answer ends the backoff",
      (result.get("limitsStale"), "backoffSeconds" in cache_file(), "backoffUntilMs" in cache_file()), (None, False, False))

clock.now += 60
answers.append(too_many)
run()
check("and a later refusal starts again from 60 s", cache_file()["backoffSeconds"], 60)

clock.now += 61
answers.append({"ok": False, "helpText": "Anthropic's usage endpoint returned status 500."})
result = run()
check("other server errors show cached numbers with the reason, without a backoff",
      (result["limitsStale"], result["limitsNote"], cache_file()["backoffSeconds"]), (True, "Anthropic's usage endpoint returned status 500.", 60))
check("(the old backoff just ran out)", clock.now > cache_file()["backoffUntilMs"] / 1000, True)

refused = {"ok": False, "helpText": "Anthropic's usage endpoint returned status 401.", "refused": True}
FIX = " Start Claude Code, or run `claude auth login`, to refresh it."
clock.now += 61
answers.append(refused)
result = run()
check("a refused sign-in says so, even with cached numbers to show",
      (result["usageStatusText"], result["limitsStale"], result["limits"], result["authHelpText"]),
      ("Sign-in expired", True, LIMITS, "Anthropic no longer accepts Claude Code's saved sign-in — showing the last known limits." + FIX))
check("and starts no backoff", clock.now > cache_file()["backoffUntilMs"] / 1000, True)

# No cached numbers at all: the problem card explains it instead.
(Path(cache) / "omarchy" / "agent-usage" / "claude-limits.json").unlink()
clock.now += 60
answers.append(too_many)
result = run()
check("rate limited with nothing cached shows the problem card",
      (result["limits"], result["usageStatusText"], result["authHelpText"].startswith("Anthropic is rate limiting checks")),
      ([], "Claude limits unavailable", True))

(Path(cache) / "omarchy" / "agent-usage" / "claude-limits.json").unlink()
answers.append(refused)
result = run()
check("a refused sign-in with nothing cached",
      (result["limits"], result["usageStatusText"], result["authHelpText"]),
      ([], "Sign-in expired", "Anthropic no longer accepts Claude Code's saved sign-in." + FIX))


def refusing(code):
  def urlopen(request, timeout):
    raise collector.urllib.error.HTTPError(request.full_url, code, "refused", {}, None)
  return urlopen


real_urlopen = collector.urllib.request.urlopen
statuses = {}
for code in (401, 403, 500):
  collector.urllib.request.urlopen = refusing(code)
  statuses[code] = real_probe(TOKEN).get("refused")
collector.urllib.request.urlopen = real_urlopen
check("401 and 403 count as a refused sign-in, other errors don't", statuses, {401: True, 403: True, 500: False})

check("retry-after parsing", [collector.parse_retry_after(v) for v in ["", "0", "120", "garbage", None]], [0.0, 0.0, 120.0, 0.0, 0.0])

print("\nall passed" if failures == 0 else f"\n{failures} failed")
sys.exit(1 if failures else 0)
