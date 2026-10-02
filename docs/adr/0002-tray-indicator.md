# 0002. Show it as a tray indicator

- Status: Superseded by [0003](0003-gnome-shell-extension.md)
- Date: 2026-10-02

## Context

Ubuntu's GNOME session ships with the *Ubuntu AppIndicators* extension
turned on. A tray indicator is the quickest way to put an icon with a label
in the top bar, and it survives GNOME upgrades well.

## Decision

The first build was a Python app using GTK 3 and AyatanaAppIndicator3:

- **Top bar:** an icon, plus the fullest limit as a label (`72%`).
- **Menu:** each limit as a text line with a meter made of characters
  (`Session ▰▰▰▰▰▰▰▱▱▱ 72% · resets in 1h 4m`), today's usage, submenus for
  tokens by day and by model, plus *Refresh now*, *Open OpenCode* and *Quit*.
- **Behaviour:** it ran the updater on its own timer, watched the usage
  folder, hid itself without data, and started at login through an autostart
  entry.

## Alternatives

- **A GNOME Shell extension.** It could look like Omarchy's panel, but it's
  more work, and extensions can break on GNOME upgrades. It was chosen in
  [0003](0003-gnome-shell-extension.md) once the look mattered.
- **A separate popup window opened from the tray icon.** On Wayland, an app
  can't place its window under the icon, so it would open mid-screen like an
  ordinary window and show up in Alt-Tab.

## Consequences (why it was replaced)

It worked, but it couldn't look like Omarchy's panel:

- **Text only:** AppIndicator menus are sent to GNOME as dbusmenu items,
  which are text lines and small icons only. Headings, real bars and a
  two-column layout aren't possible.
- **Poor meters:** the character meters rendered as uneven shapes in
  Ubuntu's font.
- **Cleanup:** `install.sh` removes this version (its process, autostart
  entry, files and commands) when it installs the extension.
