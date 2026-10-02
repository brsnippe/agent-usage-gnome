# 0014. How GNOME Shell picks up new code

- Status: Accepted
- Date: 2026-10-02

## Context

GNOME Shell only loads new or changed extension code when it starts. A first
install showed this. The installer had removed the tray version, the new
extension wasn't loaded yet, so there was no icon at all, and
`gnome-extensions info` said the extension "doesn't exist".

How to restart GNOME Shell depends on the session:

- **X11:** it can restart in place (Alt+F2 → `r`), and windows stay open.
  That turned out to be what the target laptop runs; the plan had assumed
  Wayland.
- **Wayland:** it can't restart in place. You have to log out and back in.

## Decision

- **`install.sh`** checks `XDG_SESSION_TYPE` and says what to do: Alt+F2 →
  `r` on X11, log out and back in on Wayland.
- **`diagnose.sh`** says in plain words when GNOME hasn't loaded the
  extension yet, with the same fix. It also shows the installed version, so
  it's clear which build is running.
- **`preview.sh`** opens a nested GNOME Shell in a window, running the
  installed version. That lets you check a change without logging out on
  Wayland (`--nested` up to GNOME 48, `--devkit` from 49).

## Alternatives

- **Restart GNOME Shell from the installer.** The D-Bus `Eval` route is
  disabled in current GNOME, and `gnome-shell --replace` would detach it
  from the session's service.

## Consequences

- **Every update needs a reload.** Changes to settings apply right away.
- **The old tray is removed during install,** so after an upgrade from it
  there's no icon until the reload.
