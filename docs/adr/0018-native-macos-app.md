# 0018. A native macOS menu bar app

- Status: Accepted
- Date: 2026-10-02

## Context

Coworkers with MacBooks (mostly Apple silicon, macOS 13 or newer) wanted the
same panel. The GNOME extension ([0003](0003-gnome-shell-extension.md))
can't run there, but the collectors
([0001](0001-port-omarchy-agents-widget.md)) can: they're Python. The
maintainer has no Mac. The options:

| Option | Look | Cost |
|---|---|---|
| A native Swift app | the full panel | the most work; builds only on a Mac |
| Tauri or Electron | the full panel in HTML/CSS; could reuse `usage.js` | a much heavier app (Electron ~150 MB); still built on a Mac |
| A SwiftBar plugin or Python with `rumps` | text menu only | the tray version's limits again ([0002](0002-tray-indicator.md)) |

## Decision

**A native Swift app** in `macos/`, in this repository, so it shares the
collectors and their patches. macOS 13 and up.

**Two parts:**
- **`AgentUsageCore`:** everything the panel decides without a screen,
  ported from `usage.js`, `updates.js`, `versions.js` and `terminals.js`,
  with their tests ported check for check. It uses Foundation only, so it
  builds and tests on Linux too ([0022](0022-testing-the-macos-app.md)).
- **`AgentUsage`:** the app itself (AppKit and SwiftUI), built on macOS only.

**The menu bar item:**
- the robot and the fullest limit, red from 90%, faded while the numbers are
  stale, as on GNOME;
- **always visible,** unlike on GNOME: a new app with no icon looks like a
  failed install, and the empty panel says why it's empty;
- **clicks:** left opens the panel, right (or Control-click) opens the agent,
  middle refreshes. Trackpads have no middle click; ↻ and `r` do the same.

**The panel:**
- **A borderless window** under the icon, not an `NSPopover` or SwiftUI's
  `MenuBarExtra`. Those bring an arrow, rounded corners and macOS's own
  background; Omarchy's panel is square with a 1-point border.
- **The same sections, colours and sizes** as the GNOME panel, drawn with
  SwiftUI. JetBrains Mono is bundled (SIL Open Font License), so unlike on
  Ubuntu the panel really is in JetBrains Mono.
- It closes on Esc, a click elsewhere, or switching apps, and scrolls when
  it's taller than the screen below the menu bar.

**The collectors:**
- **The app runs them itself.** `agent-usage-update` needs bash 4 and `jq`,
  and a Mac has bash 3.2. The app runs the bundled collectors side by side,
  each with a 2-minute timeout (SIGTERM, then SIGKILL 2 seconds later), and
  writes each record to a temporary file before renaming it, as the wrapper
  does. The folders are the same as on Linux.
- **Python:** Apple's Command Line Tools (3.9), Xcode's, or Homebrew's.
  Never `/usr/bin/python3`: on a Mac without the tools, that opens an
  "install the tools?" dialog instead of running, and the app would do it
  every few minutes. With no Python at all, the panel says how to install
  the tools.

**Settings and timers as on GNOME:**
- **Settings:** UserDefaults under the GNOME schema's names and defaults
  (limits every 5 minutes, rescans every 15, agent, terminal, the update
  check), in a settings window that also has **Start at login** and
  **Quit**.
- **Timers:** a refresh after unlocking and 5 seconds after waking. The
  timers don't check while the screen is locked.
- **A hidden main menu:** an app without a Dock icon shows no menu bar of
  its own, and without one Cmd-C, Cmd-V, Cmd-W and Cmd-Q don't work.

## Alternatives

- **The options in the table above.**
- **SwiftUI's `MenuBarExtra`:** it can't tell left and right clicks apart,
  and draws its own window.
- **A separate repository:** it would duplicate the collectors and their
  patches.

## Consequences

- **Two implementations of the panel:** `usage.js` and `Usage.swift`. The
  ported tests keep them in step, and a change to one needs the same change
  to the other.
- **The collectors must keep running on Python 3.9.** CI runs them with the
  Mac's own Python.
- **Opening the agent works differently on macOS**
  ([0020](0020-opening-the-agent-on-macos.md)).
- **Installing and updating work differently too**
  ([0021](0021-install-on-macos-from-the-release-zip.md)).
- **The app isn't notarized** ([0021](0021-install-on-macos-from-the-release-zip.md)).
