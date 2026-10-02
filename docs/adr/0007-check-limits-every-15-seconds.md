# 0007. Check limits every 15 seconds

- Status: Superseded by [0008](0008-rate-limit-back-off-and-stale-limits.md)
- Date: 2026-10-02

## Context

The maintainer liked seeing the percentage in the top bar and wanted it close
to live. The first request was a check every 10 seconds. But the Claude
collector won't contact Anthropic within 15 seconds of its last check
(`PROBE_MIN_INTERVAL_SECONDS`), and reuses the previous answer instead:

| Interval | Checks that reach Anthropic | Claude's numbers update |
|---|---|---|
| 10 s | every other one | about every 20 s |
| 15 s | every one | every 15 s |

## Decision

- **Default:** check limits every 15 seconds.
- **Range:** 10 to 900 seconds, as a setting.

## Alternatives

- **10 seconds, as first asked.** It looks faster, but gives slower Claude
  numbers than 15 s (see the table).
- **60 seconds.** That was suggested as a safer default before the decision,
  and set aside in favour of near-live numbers.
- **Omarchy's 15 minutes.** That's too slow for a top-bar number people
  glance at.

## Consequences (why it was replaced)

- **Anthropic's usage endpoint started refusing (HTTP 429, `retry-after: 0`).**
  At this rate the laptop made about 240 checks an hour, 60 times as many as
  Omarchy.
- **The refusals weren't visible.** On a failed check, the collector falls
  back to the last good numbers until their window resets, and says nothing.
  Meanwhile the panel's *Updated* time kept moving.
- **How it showed up:** two machines on the same account and the same 5-hour
  window showed 30% and 48% at the same minute. The laptop's 30% had been
  frozen for over 20 minutes while its token count kept climbing.
- **What replaced it:** a back-off, visible staleness and a much longer
  default ([0008](0008-rate-limit-back-off-and-stale-limits.md)).
