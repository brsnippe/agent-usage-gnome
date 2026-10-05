# 0025. The top bar shows the session limit from 40%

- Status: Accepted
- Date: 2026-10-05

## Context

The top bar showed the fullest limit across every agent and window. Claude
and Codex both have a 5-hour session window and a weekly one. Late in the
week the weekly limit is usually the fullest, so the top bar sat at, say,
80% all day. It didn't show the session limit filling up, and that's the
limit that stops you today.

The agents report no daily window. The 5-hour session window (Claude's
*Session (5-hour)*, Codex's *5h window*) is the closest, and the panel
already titles both *Session*.

## Decision

- **The session limit from a threshold on:** once the fullest session
  window reaches the threshold, the top bar shows it, even when a weekly
  window is fuller. Below the threshold it shows the fullest window, as
  before.
- **A setting, default 40%:** *Show the session limit from*, 0 to 100, under
  *Top bar* on GNOME (`session-threshold`) and *Menu bar* on a Mac
  (`sessionThreshold`). At 0 the top bar always shows the session limit,
  when there is one.
- **Compared as shown:** the rounded percentage is checked, so a session
  that reads 40% counts as 40.
- **Across agents:** the fullest session window of any agent, the same way
  the fullest window was picked before.
- **Red stays as it was:** the icon and number turn red when *any* window
  is at 90% or more, also when the number shown is the session's. Red warns
  that something is nearly full; the panel shows which.

## Alternatives

- **Always the session limit:** the weekly limit would then only show in
  the panel, also when it's nearly used up and the session is empty. The
  threshold of 0 still allows it.
- **Both numbers in the top bar** (`45% · 80%`): twice the width, for a
  number that changes slowly.
- **Red only for the number shown:** a weekly limit at 95% would then go
  unnoticed while the session is above the threshold.

## Consequences

- **`topBarPercent`** in `usage.js` and `Usage.swift` replaces
  `highestPercent` as the top bar's number. `highestPercent` stays as the
  fallback.
- **The number can be lower than the fullest limit,** so a red `45%` is
  possible. The README explains why.
- **Changing the setting applies right away,** without rebuilding the
  panel.
