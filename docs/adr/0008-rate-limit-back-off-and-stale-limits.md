# 0008. Back off on 429, mark stale limits, check every 5 minutes

- Status: Accepted (supersedes [0007](0007-check-limits-every-15-seconds.md))
- Date: 2026-10-02

## Context

Anthropic's usage endpoint rate-limits frequent checks. It answers 429 with
`retry-after: 0`, which gives no hint how long to wait. The collector made
this worse in two ways:

- **It kept going.** It tried again on every run, which prolonged the
  refusal.
- **It hid the problem.** It quietly showed the last good numbers as if
  they were current ([0007](0007-check-limits-every-15-seconds.md)).

Omarchy's own default is a check every 15 minutes, with a minimum of 30
seconds.

## Decision

**In the Claude collector**, as this project's own patch
`claude-limits-backoff.diff` ([0005](0005-collector-changes-as-patches.md)):

- **Back off after a 429.** Wait 60 s, then double on each further refusal,
  up to 900 s. A longer `retry-after`, if Anthropic ever sends one, wins.
  - The back-off is saved in the collector's cache, so it survives between
    runs.
  - It holds even against `--force`, because probing again would only
    extend the refusal.
  - The first good answer clears it.
- **Say when numbers are cached.** The record then carries `limitsStale`,
  `limitsFetchedAt` (when the numbers were measured) and `limitsNote` (why
  nothing newer is available).

**In the panel:**
- **Heading:** a yellow **LIMITS · AS OF 13:21**. Hovering it gives the
  reason, e.g. *"Anthropic is rate limiting checks · next try 13:58"*.
- **Top bar:** the percentage fades.
- **Footer:** *Updated* means when the limits were measured, not when the
  record file was last rewritten.

**The interval:** the default is **5 minutes**, with a range of 30 s to 60
min. Opening the panel still checks right away. Within 15 s of the last
check, or during a back-off, that check doesn't contact Anthropic.

## Alternatives

- **Keep 15 s and rely on the back-off alone.** The checks would keep running
  into refusals.
- **2 minutes.** That was offered, and 5 was chosen.
- **Detect staleness in the extension from the collector's cache file,**
  leaving the collector untouched. That couples the panel to a private file
  format, and wouldn't fix the hammering.

## Consequences

- **The Claude collector differs from upstream by one patch of its own.** It
  hasn't been offered upstream (yet).
- **Old settings:** a stored 15 s is below the new minimum, and GSettings
  treats a stored value outside the schema's range as unset. So installs
  moved to the new 5-minute default on their own.
- **Tests:** `test/claude-limits-test.py` covers the back-off with a fake
  clock and a fake endpoint. It checks the doubling, the cap, forced
  refreshes during a pause, recovery, other server errors, and a 429 with
  nothing cached.
