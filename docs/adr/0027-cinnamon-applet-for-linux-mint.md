# 0027. A Cinnamon applet for Linux Mint

- Status: Accepted
- Date: 2026-10-06

## Context

Coworkers on Linux Mint wanted the panel too. Mint isn't GNOME:
- **Editions:** its default and flagship edition runs **Cinnamon**, a fork of
  GNOME Shell 3 with its own panel, "applets" and settings. Mint also has
  MATE and Xfce editions.
- **Versions:**

  | Mint | Cinnamon | Base |
  |---|---|---|
  | 21.3 (supported until 2027) | 6.0 | Ubuntu 22.04 |
  | 22.3 (current, January 2026) | 6.6 | Ubuntu 24.04 |
  | 23 (due December 2026) | 6.8, with Wayland | Ubuntu 26.04 |

- **What doesn't carry over:** a GNOME Shell extension
  ([0003](0003-gnome-shell-extension.md)) doesn't run in Cinnamon.
- **What does:** Cinnamon draws with the same toolkit (St, Clutter, Cairo)
  and reads the same kind of stylesheet.

The options:

| Option | Covers | Look |
|---|---|---|
| A Cinnamon applet | Cinnamon only | the full panel, in Cinnamon's own popup under the icon |
| A standalone tray app (an XApp status icon and a popup window) | Cinnamon, MATE and Xfce | the full panel in a separate window, X11 only; a third UI to keep up |

The coworkers use the Cinnamon edition.

## Decision

**A Cinnamon applet, for Cinnamon 6.0 and up,** with the same UUID as the
GNOME extension (`agent-usage@local`). It's built from the GNOME
extension's panel ([0028](0028-shared-panel-code.md)) and installed with
the same command ([0029](0029-installing-on-cinnamon.md)).

**In the panel:**
- **A `TextIconApplet`:** the robot and the percentage, red from 90% and
  faded while stale, as on GNOME. On a vertical panel the percentage hides.
- **Always visible,** as on macOS ([0018](0018-native-macos-app.md)), not
  hidden until there's usage as on GNOME. The installer puts it on the panel
  itself, and an empty spot would look like a failed install. The empty
  panel says why it's empty.
- **Clicks as on GNOME and macOS:** left opens the panel, middle refreshes,
  **right opens the agent.** Cinnamon normally gives every applet's right
  click its own menu (*About*, *Configure…*, *Remove*). The maintainer chose
  consistency with the other platforms. In panel edit mode right-click still
  shows Cinnamon's menu, so the applet can be moved and removed.

**The popup:** Cinnamon's `AppletPopupMenu`, holding the shared panel.
- **The frame:** Mint's themes round, pad and shadow menus. The
  Cinnamon-only part of the stylesheet moves Omarchy's square, 1-pixel
  frame onto the menu's own box. Its rules name one class more than the
  theme's: St ranks rules by specificity before their order, so a later
  rule with the same specificity isn't enough.
- **Keys:** ←/→ (or h/l) and `r` are caught on the menu, as on GNOME.

**Settings: Cinnamon's own settings window** (`settings-schema.json`), opened
from the panel's ⚙ or System Settings → Applets:
- **The same keys, defaults and ranges** as GNOME's schema. A test keeps the
  two, and the agent and terminal lists, in step.
- **What's added:**
  - a *Try it* button, which opens the agent exactly as the panel does;
  - an *Update now* button;
  - the version, which the installer writes into the window's text.
- **Not installed:** agents and terminals this machine doesn't have are
  marked, as on GNOME. The applet rewrites the list's labels when it starts.

**Behaviour Cinnamon needs on top of GNOME's:**
- **Locked screen:** GNOME switches extensions off while the screen is
  locked; Cinnamon doesn't. The applet listens to `org.cinnamon.ScreenSaver`
  and pauses its timers while locked. Unlocking refreshes, as GNOME's
  re-enabling does.
- **Updates:** *vX.Y.Z available* runs `agent-usage update` in the chosen
  terminal. GNOME opens its settings window, where the Update button is.
  Cinnamon's settings window can't show live text, such as "checking for a
  newer version…".
- ***Automatic* terminal:** the terminal from Mint's Preferred Applications
  (`org.cinnamon.desktop.default-applications.terminal`) comes first. A
  terminal from the list starts its usual way; any other gets the desktop's
  own "run this" argument. Then the GNOME list.

## Alternatives

- **The standalone tray app** from the table: it would cover MATE and Xfce,
  but nobody asked for those. It would also be a third panel UI, and
  X11-only.
- **Cinnamon's right-click menu, with *Open OpenCode* and *Refresh* added:**
  more Cinnamon-like, but different from GNOME and macOS. The maintainer
  preferred the same clicks everywhere.
- **Hidden until there's usage, as on GNOME:** see above.
- **A settings window of our own (GTK):** more work for less, since
  Cinnamon's comes with the platform and looks like every other applet's.

## Consequences

- **MATE and Xfce editions aren't covered.**
- **Configure and remove** go through the panel's ⚙, panel edit mode, or
  System Settings → Applets, not a right click.
- **The settings window shows no update status;** the panel's bottom line
  does.
- **Cinnamon 6.6's settings don't watch their file.** The settings window
  tells Cinnamon over D-Bus what changed. Only the tests had to learn this
  ([0030](0030-testing-in-real-shells.md)).
- **Mint 23 (Cinnamon 6.8)** changes how applets load their modules; that's
  handled and tested ahead of its release
  ([0028](0028-shared-panel-code.md), [0030](0030-testing-in-real-shells.md)).
