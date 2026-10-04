# 0024. Check for releases every hour, and after waking

- Status: Accepted
- Date: 2026-10-04

## Context

The update check ran once a day, starting a minute after login
([0016](0016-versions-releases-and-update-check.md)), and the same on a Mac
([0021](0021-install-on-macos-from-the-release-zip.md)). The maintainer
wanted new releases to show up sooner.

Once a day was also rarer than it sounds:
- **The timers stop during sleep.** GLib's `timeout_add_seconds` counts on
  the monotonic clock, which on Linux stands still while the machine is
  suspended. A laptop that sleeps every evening and is used 8 hours a day
  checked about every three days.
- **Waking didn't check.** Waking from sleep refreshed usage, but not the
  release.

A check is cheap: one `git ls-remote` on GNOME, one call to GitHub's
releases API on a Mac.

## Decision

- **Every hour,** starting a minute after login or launch, as before.
- **After waking from sleep,** together with the usage refresh that already
  waits 5 seconds for the network. On a Mac also after unlocking: there the
  app keeps running while the screen is locked. On GNOME, unlocking already
  restarts the extension, and with it the first check after a minute.
- **Not twice in a row:** a wake or unlock skips the check when the last one
  was less than 15 minutes ago. That's measured on the wall clock, which
  does count the time asleep.
- **Still one switch** to turn it off. It's called *Check for new versions*
  now, without *daily*.

## Alternatives

- **An interval setting,** like the limits and rescan intervals: more code
  and documentation for a check that's cheap at any sensible interval.
- **Every 6 hours:** a few checks a day, but with sleeping laptops that's
  still easy to miss for a day.
- **Only shorten the interval:** sleep would still stretch it.
- **Check on every panel open:** rejected in
  [0016](0016-versions-releases-and-update-check.md) as needless traffic, and
  waking covers the case where it mattered.

## Consequences

- **More checks:** up to about 24 a day plus one per wake. On a Mac that's
  well below the API's 60 anonymous calls an hour, and the fallback to the
  release page stays.
- **No test covers the timers,** as before. The 15-minute rule lives in the
  extension and `AppModel.swift`, not in the tested modules.
