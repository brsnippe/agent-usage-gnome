# 0006. Two refresh timers and a ranked update queue

- Status: Accepted
- Date: 2026-10-02

## Context

Omarchy's widget runs a full update every 15 minutes, plus a limits-only
check when its panel opens. That leaves the top-bar percentage up to 15
minutes old. Updates come in two weights:

- **A limits check** (`--limits-only`): one request to Anthropic, plus a short
  `codex` RPC. It's cheap.
- **A full update:** it also rescans transcripts and the OpenCode database
  for the token charts.

## Decision

**When updates run:**

| Trigger | Kind |
|---|---|
| Limits timer | limits ([0008](0008-rate-limit-back-off-and-stale-limits.md) sets the interval) |
| Rescan timer (default 15 min) | normal |
| Opening the panel | limits |
| Enabling the extension (login, unlock) | normal |
| 5 s after waking from sleep (logind `PrepareForSleep`) | normal |
| Middle-click, `r`, ↻ | force |

Both intervals are settings and apply right away.

**Only one update runs at a time.** Requests that arrive meanwhile merge in
`updates.js`:

- **Rank:** force > normal > limits. A merged request takes the higher rank.
- **Dropping:** a routine request that the running update already covers is
  dropped. A forced refresh is never dropped.
- **Agents:** requests for specific agents (retries) widen when merged. An
  empty agent list means all agents.

**Rebuilding:** the panel only rebuilds when something visible changed
(`displayKey` ignores timestamps). Without this, frequent checks would reset
an open panel under the pointer. *Refreshing…* is shown only for the slower
kinds.

## Alternatives

- **Keep Omarchy's single 15-minute timer.** The top-bar number would lag too
  much.
- **The first build's queue** let the first waiting request win. With
  frequent limits checks, a waiting limits check would block the 15-minute
  full rescan, so the token charts would stop updating. Tests caught it,
  together with a second bug: `every()` on an empty agent list returns true,
  which made an all-agents request look covered by a one-agent run.

## Consequences

- **Tests:** `test/updates-test.js` covers the merging rules, including both
  bugs.
- **Battery:** GNOME switches extensions off while the screen is locked, so
  nothing runs then. Unlocking re-enables it and triggers a normal update.
