# 0017. Test without GNOME Shell

- Status: Accepted
- Date: 2026-10-02

## Context

The extension targets GNOME Shell on Ubuntu, but it was developed on an
Omarchy machine (Hyprland), which has no GNOME Shell to run it in. Installing
one there for testing would have been a large change to that system.
GitHub's test servers have no GNOME Shell either.

## Decision

**Keep the logic out of GNOME-only code.** `usage.js`, `updates.js`,
`terminals.js` and `versions.js` import nothing from GNOME Shell, so they're
tested directly with `gjs`:
- formatting;
- window titles;
- model names;
- stale limits;
- the update queue;
- terminal command lines;
- version comparison.

**Test the rest with stand-ins:**

| What | How |
|---|---|
| Settings window | Built off-screen with the real GTK 4 and libadwaita and an in-memory GSettings backend; fields and settings checked both ways |
| Claude collector's back-off | `test/claude-limits-test.py` loads the real script with a fake clock and a fake Anthropic endpoint |
| Install, update and uninstall from git | `test/cli-test.sh`, against a local bare repository with release tags; GNOME's tools (`gnome-shell`, `gsettings`, `gnome-extensions`, `dpkg-query`) replaced by small scripts |
| Installer migrations (the tray version, the old ID) | The same stand-ins, in throwaway home folders |
| Collectors | Run against real data on the development machine, with their output sent to temporary folders, so Omarchy's own widget there is never touched |

**Check what only GNOME can show on the target machine.** That covers
rendering, spacing and live behaviour. The maintainer installs the build and
reports back. When something doesn't load, `diagnose.sh` collects the
extension's state, settings, records and log lines.

## Alternatives

- **Install GNOME Shell on the development machine** and use its nested
  mode: a large change to that system, for checks the target machine does
  better.
- **Skip automated tests:** every round trip to the laptop would then catch
  bugs the tests catch in seconds. For example, the update queue bugs
  ([0006](0006-refresh-timers-and-update-queue.md)) were found by tests.

## Consequences

- **CI runs all of the automated tests**
  ([0016](0016-versions-releases-and-update-check.md)).
- **Rendering problems** only show up on the target machine.
  `preview.sh` ([0014](0014-reloading-gnome-shell.md)) shortens that loop on
  Wayland.
