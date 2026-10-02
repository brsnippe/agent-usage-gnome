# 0020. Opening the agent on macOS

- Status: Accepted
- Date: 2026-10-02

## Context

The settings of [0012](0012-configurable-agent-and-terminal.md) carry over to
the Mac app ([0018](0018-native-macos-app.md)), but two things differ:

- **Terminals are apps,** not commands on the PATH.
- **The environment is bare:** an app started at login gets launchd's PATH
  (`/usr/bin:/bin:/usr/sbin:/sbin`), without Homebrew or the per-user
  folders that agents install into. A terminal started from it gets that
  environment too.

## Decision

**Terminals:**
- **The list:** Terminal (what *Automatic* opens, since every Mac has it),
  iTerm2, Ghostty, Kitty, Alacritty, WezTerm, or *Custom*.
- **Finding them:** by bundle id, then in `/Applications`,
  `/System/Applications`, its `Utilities` folder and `~/Applications`.

**How each one starts the agent:**
- **Terminal and iTerm2** open a small `.command` script
  (`~/Library/Caches/AgentUsage/<agent>.command`) with
  `open -a <app> <script>`, the way Finder opens one. Scripting them with
  AppleScript would ask for Automation permission. The user's own shell runs
  the script, with the user's PATH.
- **Ghostty, Kitty, Alacritty and WezTerm** start with
  `open -na <app> --args <their flags> $SHELL -lic 'cd ~ && exec <agent>'`.
  The login shell gives the agent the PATH the user has in a terminal, and it
  starts in the home folder, as on GNOME.
- **Custom** works as on GNOME, with `{command}`. The command it fills in is
  the same login-shell wrapper, so `open -na Ghostty --args -e {command}`
  works.

**Finding agents:** the PATH, plus `/opt/homebrew/bin`, `/usr/local/bin` and
the per-user folders of [0012](0012-configurable-agent-and-terminal.md).

**Problems:** a missing agent or terminal opens the panel with a notice card,
instead of a notification.

## Alternatives

- **AppleScript for Terminal and iTerm2:** a permission prompt for every new
  user.
- **Running the binary inside a terminal's app bundle directly:** that ties
  the terminal to this app's process, and Ghostty doesn't support being
  started that way on macOS.

## Consequences

- **Still to confirm on a real Mac:** whether iTerm2 opens `.command` files
  this way, and each terminal's `open -na` flags. The coworker trial has to
  check these.
- **Terminal window titles** show the script's name, e.g. `OpenCode.command`.
- **The Update button** runs `agent-usage update --pause` the same way
  ([0021](0021-install-on-macos-from-the-release-zip.md)).
