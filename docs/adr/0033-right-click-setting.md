# 0033. Right-click opening the agent is a setting

- Status: Accepted
- Date: 2026-10-06

## Context

Right-clicking the robot opens the agent, on every platform: the same as
Omarchy's bar icon ([0003](0003-gnome-shell-extension.md),
[0018](0018-native-macos-app.md), [0027](0027-cinnamon-applet-for-linux-mint.md)).
Not everyone wants that:

- **A stray right-click** opens a terminal, or brings a desktop app to the
  front.
- **On Linux Mint** it replaces Cinnamon's own applet menu (*About*,
  *Configure…*, *Remove*), which every other applet has. ADR 0027 chose
  consistency with the other platforms; outside panel edit mode that menu
  was gone.

The panel's open button already opens the agent, so right-click is a
shortcut, not the only way.

**GNOME 50 broke the clicks, unnoticed.** Testing this with real clicks
turned it up. GNOME 46 to 49 open a top-bar menu in `PanelMenu.Button`'s
`vfunc_event`, which the indicator overrides. GNOME 50 opens it with a
`Clutter.ClickGesture` instead, and gestures see a press before the actor's
own `vfunc_event`. The gesture takes any button by default. On GNOME 50:

- **Right-click** opened the panel, never the agent.
- **Middle-click** opened the panel instead of refreshing.
- **Every other event** threw "Virtual function not implemented", because
  the indicator handed it on to a `vfunc_event` GNOME 50 no longer has.

The smoke test hadn't caught it: it called `vfunc_event` itself, past the
gesture ([0030](0030-testing-in-real-shells.md)).

## Decision

- **A switch, *Right-click opens the agent*,** in the *Open agent* group of
  the settings, on all three platforms. On by default, so nothing changes
  for anyone who doesn't touch it.
- **Switched off, right-click does what the desktop does by itself:**
  - **GNOME:** opens the panel, as left-click does.
  - **Linux Mint:** Cinnamon's own applet menu.
  - **Mac:** opens the panel, as left-click does. Control-click, the Mac's
    other right-click, follows the switch too.
- **The panel's open button** and the settings' *Try it* keep opening the
  agent either way.
- **Keys:** `right-click-opens-agent` on GNOME and Mint,
  `rightClickOpensAgent` on a Mac. The hosts read it at the moment of the
  click, so nothing needs to listen for changes.
- **GNOME 50's gesture only takes the left button.** The middle and right
  buttons reach the indicator's `vfunc_event` again, on every GNOME
  version. With the switch off, the indicator opens the panel itself.
  Events go on to `PanelMenu.Button`'s `vfunc_event` only where it has one.

## Alternatives

- **Open the panel everywhere:** the same on all three, but Mint users would
  still only get Cinnamon's menu in panel edit mode.
- **Ignore right-click when off:** a click that does nothing looks broken.
- **A choice of what right-click does** (agent, panel, refresh): more to
  explain, for something nobody asked for.
- **Catch the middle and right buttons in the capture phase on GNOME 50,**
  before the gesture: more code, and it works against the gesture instead
  of telling it which button is its own.

## Consequences

- **Mint gets Cinnamon's menu back** for those who want it, the alternative
  ADR 0027 turned down for the default.
- **Settings in four places** get one more key: the gschema, `prefs.js`,
  `settings-schema.json` and the Mac's `Settings`. The Cinnamon settings test
  checks the first and third match.
- **The indicator sets `_clickGesture`,** a field of GNOME 50's
  `PanelMenu.Button`, not an API. If GNOME renames it, middle and right
  clicks open the panel again, and the smoke test on 26.04 fails.
- **The Mac settings window** is 40 points taller, for the extra row.
- **Tests:**
  - **GNOME's smoke test clicks through a virtual pointer,** not
    `vfunc_event`: right, middle and left, then right with the switch off.
    Run against the old code on GNOME 50, it fails.
  - **Cinnamon's** switches it off and right-clicks through the handler, as
    before; Cinnamon's menu opens, with a screenshot (`applet-menu`).
  - **The Mac's switch** has only been built in CI.
