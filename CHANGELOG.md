# Changelog

Versions are git tags (`v0.6.0`, …). `agent-usage update` installs the newest
one.

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
