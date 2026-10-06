# Changelog

Versions are git tags (`v0.6.0`, …). `agent-usage update` installs the newest
one.

## 0.13.0

⏻ in the panel switches it off. On GNOME, Linux Mint and a Mac.

- **⏻ after ⚙** in the panel's header, and `q` while the panel is open. An
  empty panel has ⚙ and ⏻ too. See the README's *Switching it off* section.
  - **Mac:** quits right away, and so does ⌘Q in the panel. It starts again
    at login, or from Spotlight.
  - **GNOME:** asks first, then switches the extension off, as the
    Extensions app does. It stays off, also after you log in again, until
    you switch it back on there or with
    `gnome-extensions enable agent-usage@local`.
  - **Linux Mint:** asks first, then takes the applet off the panel, as
    Cinnamon's *Remove* does. Right-click the panel, *Applets*, to add it
    back; your settings are kept.
  - **Nothing is lost:** settings, usage data and the session colors' hooks
    stay.
- **`agent-usage diagnose`** on GNOME shows `disabled-extensions` too.
- **Tests:** switching off and back on, in the real GNOME Shell and
  Cinnamon, with a screenshot of the question.

## 0.12.0

The robot says when an agent wants you. On GNOME, Linux Mint and a Mac.

- **Session colors:** the robot turns orange while a Claude Code or OpenCode
  session waits for you (a permission, a question, a plan to approve), and
  green once one has finished its turn. Opening the panel, or right-clicking
  to open your agent, clears the green. See the README's *Session colors*
  section.
  - A limit at 90% or more still turns the percentage red.
  - **What it adds:** hooks in Claude Code's settings and a plugin in
    OpenCode 2, next to your own. This update adds them too, and says so.
    The panel adds them whenever it starts, so an agent you install later
    gets them as well.
  - **Switching it off:** *Session colors* in the settings switches it off
    and takes the hooks and the plugin out again. `agent-usage uninstall`
    takes them out too.
- **`agent-usage diagnose`** shows what's installed for the session colors,
  and every session's state.
- **Tests:** the hooks and the plugin, against a stand-in OpenCode, and the
  colors in the real GNOME Shell and Cinnamon, with screenshots.

## 0.11.0

Linux Mint. And JetBrains Mono, on GNOME too.

- **Linux Mint:** the same panel as a Cinnamon applet, for Cinnamon 6.0 and
  up (Mint 21.3, 22.x, LMDE 6 and 7). The same `get.sh` line installs it,
  puts the robot in the panel and loads it, without logging out. Updates
  reload it in place. See the README's *Linux Mint* section.
  - Clicks as on GNOME: left opens the panel, middle refreshes, right opens
    your agent.
  - Settings in Cinnamon's own window (⚙ in the panel, or System Settings →
    Applets), with GNOME's options plus *Try it* and *Update now*.
  - *Automatic* opens the terminal from Mint's Preferred Applications.
- **The panel's font:** it now really is JetBrains Mono, on GNOME as on
  Cinnamon. GNOME Shell had been ignoring the whole font list because of how
  its second name was quoted.
- **Under the hood:** the panel moved from `extension.js` into `panel.js`,
  which GNOME and Cinnamon share. GNOME's behaviour doesn't change.
- **Tests:** CI now runs the extension in a real, headless GNOME Shell (46
  and 50), and the applet in a real Cinnamon on Linux Mint, with screenshots
  of both.

## 0.10.0

The all-time token total. On GNOME and on a Mac.

- **All time by model:** the heading shows the agent's total tokens of all
  time, e.g. `ALL TIME BY MODEL · 1.2B`. It counts every model, cache
  included, not just the four listed.
- **Hover the heading** for the sessions, prompts and active days behind
  it.

## 0.9.0

The top bar follows the session limit once it fills up. On GNOME and on a
Mac.

- **Top bar:** once the 5-hour session limit is 40% full, the top bar shows
  it, even when the weekly limit is fuller. Below that it still shows the
  fullest limit. It still turns red when any limit reaches 90%.
- **Settings:** *Show the session limit from* sets the percentage, from 0 to
  100. It's under *Top bar* on GNOME and *Menu bar* on a Mac. At 0 the top
  bar always shows the session limit.

## 0.8.1

New releases show up sooner. On GNOME and on a Mac.

- **Updates:** the panel checks for a new version every hour instead of once
  a day, and also after the computer wakes from sleep (on a Mac, also after
  unlocking). The daily timer stopped while the computer slept, so on a
  laptop it often ran only every few days.
- **Settings:** the switch is now called *Check for new versions*.

## 0.8.0

Desktop apps, and signing in again from the panel. On GNOME and on a Mac.

- **Desktop apps:** *Agent* in the settings has two more choices,
  *OpenCode (desktop app)* and *Claude (desktop app)*. The open button and
  right-click then open the app, or bring it to the front. The button shows
  an app icon.
- **Sign-in buttons:** when the sign-in is the problem, the problem card
  offers the fix, in your terminal:
  - **Claude Code** (*Sign-in expired*, *Waiting for auth*):
    **Start Claude Code**, which refreshes the saved sign-in, or
    **Sign in** (`claude auth login`).
  - **Codex** (*Not signed in*): **Sign in** (`codex login`).

  After **Sign in**, the window waits for Enter, so you can read how it
  went. The panel then checks every 15 seconds until the problem is gone.
- **Collectors:** two new patches of this project's own.
  - `claude-sign-in-refused.diff`: when Anthropic refuses the saved
    sign-in, the panel says *Sign-in expired*, instead of a generic error
    that cached limits could hide.
  - `codex-sign-in.diff`: a signed-out Codex says *Not signed in*, instead
    of nothing.
- **Settings:** the terminal is also used for signing in and updating, also
  when the agent is a desktop app. The settings say so now.

## 0.7.0

The same panel on a Mac, as a native menu bar app (macOS 13 and up, Apple
silicon and Intel). Nothing changes on GNOME.

- **Install:** the same `curl … get.sh | bash` line. On a Mac it downloads
  the app from this release, installs it in `~/Applications` with the
  `agent-usage` command, and starts it. It starts at login from then on.
- **Menu bar:** the robot and the fullest limit, red at 90%, faded while
  stale. Unlike on GNOME, the robot is always there.
- **Panel:** every section of the GNOME panel, in Kanagawa and JetBrains
  Mono.
  - Left-click opens it, right-click or Control-click opens your agent, and
    a middle-click refreshes.
  - ←/→, h/l, `r` and Esc work as on GNOME.
- **Settings:** the GNOME options (refresh intervals, agent, terminal,
  update check), plus *Start at login* and *Quit*.
- **Terminals:** Terminal, iTerm2, Ghostty, Kitty, Alacritty, WezTerm, or a
  custom command. The agent starts in your login shell.
- **Updates:** a daily check, the *vX.Y.Z available* notice, and an Update
  button that installs the new version and restarts the app.
- **Commands:** `agent-usage update`, `version`, `diagnose` and
  `uninstall [--purge]`.
- **Claude on a Mac:** a new patch, `claude-macos-keychain.diff`, lets the
  Claude collector read Claude Code's login from the macOS Keychain. On
  Linux it changes nothing.

## 0.6.0

The first tagged release. It brings together everything from the
hand-delivered builds 1–6:

- **Panel:** Omarchy's Agents panel as a GNOME Shell extension (GNOME 46+),
  in Omarchy's Kanagawa look. It has a header, agent tabs and a problem card,
  plus Limits, Tokens by day, Today by model and All time by model sections.
  Hovering a row shows details in the bottom line.
- **Top bar:** the fullest limit as a percentage. It turns red at 90% and
  fades while the numbers are from an earlier check.
- **Refreshing:**
  - Limits every 5 minutes (adjustable, 30 s – 60 min) and whenever the panel
    opens.
  - A full rescan every 15 minutes (adjustable), and after unlocking or waking
    from sleep.
  - By hand: middle-click, `r`, or ↻.
- **Rate limits:** when Anthropic answers 429, Claude limit checks back off
  (1, 2, 4, 8, up to 15 minutes). Cached limits are shown as
  *LIMITS · AS OF HH:MM*, with the reason on hover.
- **Opening an agent:** the agent (OpenCode, Claude Code, Codex, custom) and
  the terminal (Ghostty, GNOME Terminal, Ptyxis, Kitty, Alacritty, WezTerm,
  Foot, Konsole, xterm, custom) are both settings, with a *Try it* button.
- **Settings window** in GNOME's Extensions app, or from the panel's ⚙.
- **OpenCode v2:** usage is counted, via the upstream fixes from Omarchy PRs
  #13894 and #7686, applied as patches.
- **Installs from git:** `get.sh` installs it, `agent-usage update` updates
  it, and the panel says when a new version is out.
