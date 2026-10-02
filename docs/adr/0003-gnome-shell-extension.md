# 0003. A GNOME Shell extension in Omarchy's Kanagawa look

- Status: Accepted (supersedes [0002](0002-tray-indicator.md))
- Date: 2026-10-02

## Context

The goal was the panel to look like Omarchy's, which the tray menu couldn't
manage. The target laptop runs GNOME 46 (Ubuntu 24.04).

## Decision

**The extension:**
- It uses the module format of GNOME 45 and up (`export default class …
  extends Extension`).
- `metadata.json` lists shell versions 46–50.
- A `PanelMenu.Button` in the top bar holds the icon and the fullest limit.
  Its popup holds a custom `St` layout, which follows Omarchy's `Panel.qml`
  section by section: header with logo, name and plan; agent tabs; a problem
  card; Limits; Tokens by day; then the model sections
  ([0010](0010-model-sections.md)).

**The look:**
- **Bars** are drawn with Cairo in `St.DrawingArea`, so their ends can be
  rounded.
- **Colors** come from Omarchy's Kanagawa theme:

  | Use | Color |
  |---|---|
  | background | `#1f1f28` |
  | text and border | `#dcd7ba` |
  | dimmed text | `#8e8b78` |
  | urgent (90% and up) | `#c34043` |
  | stale | `#c0a36e` |

- **Font:** the stylesheet asks for JetBrains Mono, and the installer
  installs `fonts-jetbrains-mono`.

**Controls:**
- **Mouse:** left-click opens the panel, middle-click refreshes, right-click
  opens the agent, as on Omarchy.
- **Keyboard:** with the panel open, ←/→ (or h/l) switch agents, `r`
  refreshes and Esc closes.
- **Arrow keys:** GNOME uses ←/→ to move between top-bar menus. The panel
  therefore catches them on the menu (`captured-event`), and only when there
  are tabs to switch.

## Alternatives

- **Keep the tray indicator** ([0002](0002-tray-indicator.md)): it can't do
  the layout.
- **A popup window opened from the tray icon:** on Wayland it can't be placed
  under the icon.
- **Follow Ubuntu's light/dark style instead of Kanagawa:** that wouldn't
  look like Omarchy, which was the point.

## Consequences

- **Reloading:** GNOME only loads new extension code when it starts
  ([0014](0014-reloading-gnome-shell.md)).
- **GNOME upgrades:** a new major version may need an entry in
  `shell-version`, or API fixes.
- **The font:** on Ubuntu the panel renders in the system font instead of
  JetBrains Mono. That was noticed and left as is.
- **Testing:** this code can't run on the development machine, which has no
  GNOME Shell ([0017](0017-testing-without-gnome-shell.md)).
