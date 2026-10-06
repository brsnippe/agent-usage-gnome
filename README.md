# Agent Usage for GNOME, Cinnamon and macOS

Omarchy's **Agents** panel as a GNOME Shell extension, in Omarchy's Kanagawa
look. It shows Claude Code and Codex rate limits with reset countdowns, plus
tokens by day and by model. That includes sessions you ran in **OpenCode v2**.

On Linux Mint it's the same panel as a Cinnamon applet: see
[Linux Mint](#linux-mint). On a Mac it's the same panel under a menu bar
icon: see [macOS](#macos).

- **Top bar:** a robot icon with your fullest limit (`61%`). It turns red at
  90% or more. It stays hidden until an agent has usage to show. See
  [Which limit the top bar shows](#which-limit-the-top-bar-shows).
- **Session colors:** the robot turns orange while a Claude Code or OpenCode
  session waits for you, and green once one has finished its turn. See
  [Session colors](#session-colors).
- **Panel:**
  - **Header:** the agent's logo, name and plan, with refresh, *Open agent*,
    ⚙ settings and ⏻ buttons. ⏻ switches it off: see
    [Switching it off](#switching-it-off).
  - **Tabs:** one per agent, if you have more than one.
  - **Problem card:** shows up when something needs fixing (sign-in,
    missing CLI). When the sign-in is the problem, its buttons fix it: see
    [Signing in again](#signing-in-again).
  - **Sections:**
    - **Limits** and **Tokens by day.**
    - **Today by model:** today's tokens per model, with each model's share of
      the day on hover.
    - **All time by model:** the agent's all-time token total in the
      heading (`ALL TIME BY MODEL · 1.2B`), then the top 4 models with the
      in/out/cache split on hover. The total counts every model, cache
      included, not just the four listed. Hovering the heading shows the
      sessions, prompts and active days behind it. For Codex, "all time" is
      about the last 30 days: its collector only reads Codex sessions and
      OpenCode usage from that long ago.

    All of them use real bars, and hovering a row shows details in the
    bottom line. On a small screen the panel scrolls rather than running off
    the bottom.
- **Mouse:** left-click opens the panel, middle-click refreshes, right-click
  opens your agent (OpenCode by default) in a terminal, or a desktop app.
- **Keyboard (panel open):** ←/→ (or h/l) switches agent, `r` refreshes,
  `q` does what ⏻ does, Esc closes.

## Linux Mint

The same panel as a Cinnamon applet, for Mint's default edition: Cinnamon
6.0 and up, so Mint 21.3, 22.x and LMDE 6 and 7. Mint's MATE and Xfce
editions aren't covered.

### Install on Linux Mint

The same line as on GNOME:

```bash
curl -fsSL https://raw.githubusercontent.com/brsnippe/agent-usage-gnome/main/get.sh | bash
```

It clones and installs as on GNOME (see [Install](#install)), and then:

- puts the robot in the panel, at the right, next to the status icons;
- loads it right away. There's no logging out, also not after an update:
  Cinnamon reloads the applet in place.

### What's different from GNOME

- **The robot is always in the panel,** as on a Mac, even before there's
  usage to show. The open panel says why it's empty.
- **Clicks are GNOME's:** left opens the panel, middle refreshes, right opens
  your agent. In panel edit mode, right-click shows Cinnamon's own menu
  instead, to move or remove the applet.
- **On a vertical panel** only the robot shows, without the percentage.
- **Settings:** the panel's ⚙ button, or System Settings → Applets →
  Agent Usage. It's Cinnamon's own settings window with GNOME's options, plus
  *Try it* and *Update now* buttons.
- **Terminals:** *Automatic* means the terminal from System Settings →
  Preferred Applications (GNOME Terminal on a new Mint), then GNOME's list.
- **Locked screen:** the applet pauses its checks until the screen is
  unlocked, then refreshes, as GNOME does.
- **Updates:** *vX.Y.Z available* in the bottom line runs
  `agent-usage update` in your terminal. Cinnamon reloads the applet when
  it's done.
- **⏻** takes the applet off the panel, after asking. See
  [Switching it off](#switching-it-off).

The `agent-usage` commands are the same as on GNOME (see [Update](#update)).

### Where things are on Linux Mint

| What | Where |
|---|---|
| The applet | `~/.local/share/cinnamon/applets/agent-usage@local/` |
| Settings | `~/.config/cinnamon/spices/agent-usage@local/` |
| Usage records | `~/.local/state/omarchy/agents/usage/`, as on GNOME |
| Session states | `~/.local/state/omarchy/agents/sessions/`, as on GNOME |
| Log | Cinnamon's; `agent-usage diagnose` shows the applet's lines |

## macOS

The same panel as a menu bar app, for macOS 13 (Ventura) and up, on Apple
silicon and Intel.

### Install on a Mac

```bash
curl -fsSL https://raw.githubusercontent.com/brsnippe/agent-usage-gnome/main/get.sh | bash
```

On a Mac, `get.sh`:

- downloads the newest release's app (no git, no GitHub account);
- installs it as `~/Applications/Agent Usage.app` (no admin password);
- adds the `agent-usage` command to `~/.local/bin`;
- starts it. From then on it starts at login.

The collectors need Python 3, which comes with Apple's Command Line Tools.
Most developers have them already, since git needs them too. Otherwise:

```bash
xcode-select --install
```

Sign in to the agents you use, as on Linux (`claude auth login`,
`codex login`). On a Mac, Claude Code keeps its login in the Keychain, and
that's where the Claude collector reads it.

**Downloaded the zip in a browser instead?** macOS then refuses to open the
app, because Apple hasn't notarized it. Fix that once with:

```bash
xattr -dr com.apple.quarantine "Agent Usage.app"
```

### What's different from GNOME

- **The robot is always in the menu bar,** even before there's usage to show.
- **Clicks:**
  - left-click opens the panel;
  - right-click (a two-finger click on a trackpad) or Control-click opens your
    agent;
  - middle-click refreshes, on a mouse.

  The keys are the same as on GNOME.
- **Settings:** the panel's ⚙ button, or open Agent Usage again from Finder or
  Spotlight. The options are GNOME's, plus *Start at login* and *Quit*.
- **Quitting:** the panel's ⏻ button, `q` or ⌘Q quits right away. See
  [Switching it off](#switching-it-off).
- **Terminals:** *Automatic* means Terminal. You can also pick iTerm2,
  Ghostty, Kitty, Alacritty or WezTerm, or write a custom command such as
  `open -na Ghostty --args -e {command}`. The agent starts in your login
  shell, so it finds the same tools as in a terminal window.
- **Desktop apps:** *Claude (desktop app)* opens `Claude.app`, and
  *OpenCode (desktop app)* opens `OpenCode.app`, with `open -a`.
- **Updates:** the panel checks GitHub every hour, and after the Mac wakes or
  unlocks. *vX.Y.Z available* in its bottom line opens the settings, where
  **Update** installs the new version and restarts the app. Nothing needs
  reloading.

### Commands on a Mac

```bash
agent-usage update               # install the newest release
agent-usage version              # installed version, and the newest release
agent-usage diagnose             # what to paste when something looks wrong
agent-usage uninstall            # remove the app and the session hooks (--purge: also data, settings, logs)
```

### Where things are on a Mac

| What | Where |
|---|---|
| The app | `~/Applications/Agent Usage.app` |
| Usage records | `~/.local/state/omarchy/agents/usage/`, as on Linux |
| Session states | `~/.local/state/omarchy/agents/sessions/`, as on Linux |
| Settings | the `io.github.brsnippe.agent-usage` defaults |
| Log | `~/Library/Logs/AgentUsage/agent-usage.log` |

## Refreshing

| What | When |
|---|---|
| Rate limits (the top-bar `%`) | Every **5 minutes** (adjustable), and right away when you open the panel |
| Full rescan (token charts) | Every **15 minutes** (adjustable), at login, after unlocking, and a few seconds after waking from sleep |
| By hand | Middle-click the icon, press `r` in the panel, or use its ↻ button |

To change the intervals, use the panel's ⚙ button, the *Settings* button for
Agent Usage in the **Extensions** app, or
`gnome-extensions prefs agent-usage@local`. Changes apply right
away.

- **Limits** can be checked every 30 seconds to 60 minutes. Omarchy's own
  widget checks every 15 minutes.
- **Rate limiting:** Anthropic refuses checks that come too often (HTTP 429),
  even at 15-second intervals. When it does, the collector pauses checking:
  1 minute, then 2, 4, 8, up to 15, and back to normal after the first good
  answer. During a pause, even a manual refresh doesn't contact Anthropic,
  since that would only prolong it.
- **Stale numbers are marked:**
  - While the panel shows limits from an earlier check, the heading turns
    yellow and reads **LIMITS · AS OF 13:21**. Hovering it says why, e.g.
    *"Anthropic is rate limiting checks · next try 13:58"*.
  - The top-bar percentage fades until fresh numbers arrive.
  - The *Updated* time at the bottom is when the limits were actually
    measured.
- **Full rescans** can run every 5 to 60 minutes.
- **No checks while locked:** GNOME switches extensions off while the screen
  is locked, so nothing runs while you're away. On Cinnamon the applet pauses
  itself.

## Which limit the top bar shows

- **Usually the fullest limit,** whichever agent and window it belongs to.
- **The 5-hour session limit once it's 40% full,** even when the weekly limit
  is fuller. That's the one that stops you today. Set the percentage under
  *Top bar* in the settings (*Menu bar* on a Mac), from 0 to 100. At 0 the
  top bar always shows the session limit.
- **Red** still means *any* limit is at 90% or more, also when the top bar
  shows the session.

## Session colors

The robot shows what your Claude Code and OpenCode sessions want:

| Robot | When |
|---|---|
| **Orange** | A session waits for you: a permission prompt, a question, a plan to approve, an MCP server asking for input |
| **Green** | A session finished its turn, and you haven't opened the panel since |
| Its usual color | Sessions working, idle, or finished and seen |

- **Clearing green:** open the panel, or right-click to open your agent. The
  next finished turn turns it green again.
- **Orange** only goes away once the session moves on: answer it in the
  agent.
- **Several sessions:** orange if any of them waits, green if any finished
  turn is unseen.
- **Subagents:** one waiting for a permission turns the robot orange; one
  finishing doesn't turn it green.
- **Red:** a limit at 90% or more keeps the percentage red. The robot itself
  only turns red when no session wants anything.
- **Left out:** sessions whose agent has quit (say, a closed terminal), and
  sessions nobody touched for a day.

### How it hooks in

- **Claude Code:** hooks in `~/.claude/settings.json` (or in
  `$CLAUDE_CONFIG_DIR`), after your own. They run
  `~/.local/bin/agent-usage-session`, which notes each session's state in a
  small file. Claude Code picks up the change by itself.
- **OpenCode 2:** a plugin, `~/.config/opencode/plugins/agent-usage.js`,
  which OpenCode loads by itself. OpenCode 1 loads plugins differently, so
  it gets none.
- **When they're added:** the installer and every update add them, and say
  so. The panel does it too whenever it starts, so an agent you install
  later gets them as well. An agent that isn't installed gets nothing.
- **Switching it off:** *Session colors* in the settings (under *Top bar* on
  GNOME, *Panel* on Linux Mint, *Menu bar* on a Mac). That takes the hooks
  and the plugin out again, and they stay out until you switch it back on.
  `agent-usage uninstall` takes them out too.
- **After the first install on GNOME:** the hooks work right away, but the
  robot only changes color once GNOME has reloaded the extension (see
  [After installing or updating](#after-installing-or-updating)).
- **Seeing what's going on:** `agent-usage diagnose` shows what's installed
  and every session's state.

Claude Code has no hook for approving a permission. After you approve one,
the robot stays orange until that tool has finished.

## Opening your agent

The panel's open button, and right-clicking the top-bar icon, open an agent
in a terminal, or a desktop app. Both are set in the same settings window,
under *Open agent*:

- **Agent:**
  - **In a terminal:** OpenCode (the default), Claude Code, Codex, or
    *Custom…*. Custom takes any command, e.g. `claude --continue`.
  - **Desktop apps:** *OpenCode (desktop app)* and *Claude (desktop app)*.
    The button then shows an app icon, and an app that's already open comes
    to the front. Claude's desktop app is in beta on Linux, for Ubuntu and
    Debian.

  Agents that aren't installed are marked.
- **Terminal:** *Automatic* (the default) uses the desktop's default
  terminal, which is GNOME Terminal on stock Ubuntu. Signing in and updating
  use it too, also when the agent is a desktop app. Or pick one of the
  installed terminals:

  | Terminal | Started as |
  |---|---|
  | Ghostty | `ghostty -e <agent>` |
  | GNOME Terminal | `gnome-terminal -- <agent>` |
  | Ptyxis | `ptyxis --new-window -x '<agent>'` |
  | Kitty | `kitty <agent>` |
  | Alacritty | `alacritty -e <agent>` |
  | WezTerm | `wezterm start -- <agent>` |
  | Foot | `foot <agent>` |
  | Konsole | `konsole -e <agent>` |
  | xterm | `xterm -e <agent>` |

  For any other terminal or extra flags, pick *Custom…*. Write the command
  with `{command}` where the agent goes, e.g.
  `ghostty --window-decoration=false -e {command}`. Without `{command}`, the
  agent goes at the end.
- **Try it:** shows the exact command that will run, and its *Open* button
  runs it.

The terminals and agents are looked up on your PATH, plus `~/.local/bin`,
`~/.opencode/bin`, `~/.npm-global/bin`, `~/.bun/bin`, `~/.cargo/bin`, mise's
shims and `/snap/bin`. If the terminal you picked goes missing, you get a
notification saying so, rather than a different terminal opening.

The desktop apps are found by their desktop file
(`ai.opencode.desktop.desktop`, `claude-desktop.desktop`), or by any desktop
file that runs `ai.opencode.desktop` or `claude-desktop`. An OpenCode
AppImage at `~/Applications/OpenCode.AppImage` works too.

Made for GNOME 46 (Ubuntu 24.04) and up.

## Signing in again

Claude Code's saved sign-in runs out when Claude Code hasn't run for a
while, and a sign-in elsewhere can replace it. The panel then says *Sign-in
expired*, or *Waiting for auth* when there's none at all. Codex says *Not
signed in*. The problem card offers the fix:

| Agent | Button | Runs |
|---|---|---|
| Claude Code | **Start Claude Code** | `claude`, which refreshes the saved sign-in by itself |
| Claude Code | **Sign in** | `claude auth login` |
| Codex | **Sign in** | `codex login` |

- **Where:** in the terminal from the settings, even when *Agent* is a
  desktop app. The desktop apps keep their own sign-in, which the panel
  doesn't read.
- **Reading the outcome:** after **Sign in**, the window waits for Enter
  before it closes.
- **Afterwards:** the panel checks that agent's limits every 15 seconds,
  for up to 5 minutes, until the problem is gone. There's no need to
  refresh by hand.

## Switching it off

The panel's ⏻ button, or `q` while the panel is open, stops Agent Usage: no
more checks, and the robot leaves the top bar. It's there in an empty panel
too.

| | ⏻ | Back on |
|---|---|---|
| **GNOME** | Asks, then switches the extension off, as the Extensions app does | The Extensions app, or `gnome-extensions enable agent-usage@local`. An update switches it back on too |
| **Linux Mint** | Asks, then takes the applet off the panel, as Cinnamon's *Remove* does | Right-click the panel, *Applets*, then add *Agent Usage*. An update leaves it off |
| **Mac** | Quits right away | At the next login, or open Agent Usage from Spotlight or Finder |

- **It stays off** on GNOME and Mint, also after you log in again. A
  notification says how to switch it back on.
- **Nothing is lost:** your settings and usage data are kept.
- **The session colors' hooks stay** in Claude Code and OpenCode, writing
  their small files for when the panel is back. `agent-usage uninstall` takes
  them out.

## Install

This and the next sections are about GNOME. Linux Mint uses the same
commands; what's different there is under [Linux Mint](#linux-mint). On a
Mac, see [Install on a Mac](#install-on-a-mac).

```bash
curl -fsSL https://raw.githubusercontent.com/brsnippe/agent-usage-gnome/main/get.sh | bash
```

`get.sh` does three things:

- clones this repository into `~/.local/share/agent-usage-gnome`;
- checks out the newest release;
- runs `install.sh`, which also adds the `agent-usage` command.

You don't need a GitHub account. If you'd rather look at the script before
running it:

```bash
git clone https://github.com/brsnippe/agent-usage-gnome.git ~/.local/share/agent-usage-gnome
~/.local/share/agent-usage-gnome/get.sh
```

## Update

```bash
agent-usage update     # install the newest release
agent-usage version    # installed version, and the newest release
```

The panel checks every hour, and after the computer wakes from sleep. When a
new version is out, its bottom line says *v0.6.1 available*. Clicking that
opens ⚙, where **Update** runs `agent-usage update` in your terminal. The
check can be switched off there.

Other commands:

- `agent-usage update --main`: the latest commit instead of the newest
  release, for testing.
- `agent-usage diagnose`: what to paste when something looks wrong.
- `agent-usage uninstall`: remove it, and the session colors' hooks. Add
  `--purge` to also delete the usage data and settings.

## After installing or updating

GNOME only picks up new or changed extension code when it starts. Then:

- **X11** (`echo $XDG_SESSION_TYPE` prints `x11`): press **Alt+F2**, type
  **`r`**, press **Enter**. GNOME Shell restarts in place, and your windows
  stay open.
- **Wayland:** log out and back in. To look at a change without logging out,
  run `./preview.sh`. It opens a second GNOME Shell in a window.

Until then the icon isn't in the top bar. If you're upgrading from the tray
version, it disappears as soon as you run the installer.

The installer:

1. Installs `python3`, `jq`, `fonts-jetbrains-mono` and `libglib2.0-bin` with
   apt, if they're missing.
2. Removes earlier versions if they're installed, keeping your usage data
   and settings:
   - **The tray-icon version:** its process, autostart entry, files and
     commands.
   - **The first extension build:** it was named
     `agent-usage@brsnippe.github.io`.
3. Copies the extension to
   `~/.local/share/gnome-shell/extensions/agent-usage@local/`.
   It replaces any previous copy, compiles its settings and turns it on. Your
   chosen intervals are kept across reinstalls.
4. Adds the [session colors](#session-colors)' hooks to Claude Code and
   their plugin to OpenCode 2, unless you've switched them off.
5. Collects usage once and prints what it found.

Everything is per user. Each person's install reads their own Claude Code
login, OpenCode history and Codex login, and keeps its data in their own home
folder. It only connects to Anthropic and to Codex (through the `codex` CLI),
to read that person's rate limits.

Installing from a downloaded copy without git (`./install.sh`) still works,
but that copy can't update itself.

Sign in to the agents you use, or no limits will show:

```bash
claude auth login   # Claude Code limits
codex login         # Codex limits (needs the Codex CLI installed)
```

Later on, the panel's problem card has buttons for that
([Signing in again](#signing-in-again)).

## When something looks wrong

Run `agent-usage diagnose` (or `./diagnose.sh`) and paste its output. It shows the GNOME version, whether
the extension loaded or failed, the usage records and the extension's lines
from the GNOME Shell log. On Linux Mint it shows the same for Cinnamon and
the applet, including its settings and where it sits in the panel.

## How it works

Why it's built this way, decision by decision:
[docs/adr/](docs/adr/README.md).

The extension lives in `agent-usage@local/`:

| Piece | What it does |
|---|---|
| `bin/agent-usage-claude` | Claude Code limits (Anthropic's usage endpoint) and token stats. The stats come from `~/.claude/projects` plus OpenCode sessions on the `anthropic` provider |
| `bin/agent-usage-codex` | Codex limits (`codex app-server`) and token stats. The stats come from Codex sessions plus OpenCode sessions on the `openai` provider |
| `bin/agent-usage-update` | Runs the collectors and writes one JSON file per agent to `~/.local/state/omarchy/agents/usage/`. It's also on your PATH, so `agent-usage-update --force` collects again by hand |
| `hooks/agent-usage-session` | The [session colors](#session-colors)' hook for Claude Code, which writes one small file per session to `~/.local/state/omarchy/agents/sessions/`. Its `install`, `uninstall` and `status` add and remove the hooks in Claude Code and the plugin in OpenCode. Outside `bin/`, where everything is a collector |
| `hooks/opencode-agent-usage.js` | The OpenCode 2 plugin that writes the same files for OpenCode sessions |
| `panel.js`, `usage.js`, `sessions.js`, `updates.js`, `stylesheet.css` | The panel. It schedules the updater, displays those JSON files, and colors the robot by the session files. The Cinnamon applet uses the same files |
| `extension.js` | GNOME's top-bar button and the menu around the panel |
| `terminals.js` | Which agent or desktop app to open, how to start each terminal, and the sign-in commands. The panel and the settings window both use it |
| `versions.js` | Compares release versions for the update notice |
| `prefs.js`, `schemas/` | The settings window and its settings: the refresh intervals, which limit the top bar shows, the session colors, the agent, the terminal and update checks |

Around it, in the repository:

| Piece | What it does |
|---|---|
| `get.sh` | First install from git |
| `bin/agent-usage` | `update`, `version`, `latest`, `diagnose`, `uninstall` |
| `install.sh`, `uninstall.sh`, `diagnose.sh`, `preview.sh` | Install, remove, debug and preview the extension. In a Cinnamon session the first three hand over to `cinnamon/` |
| `scripts/common.sh` | What the GNOME and Cinnamon scripts share |
| `VERSION`, `CHANGELOG.md`, `scripts/release.sh` | Releases (see [Releasing](#releasing)) |
| `patches/`, `test/` | The changes to Omarchy's collectors, and the tests |
| `cinnamon/` | The Cinnamon applet: see below |
| `macos/` | The macOS app: see below |

The Cinnamon applet lives in `cinnamon/` and is built from the extension's
panel when it's installed:

| Piece | What it does |
|---|---|
| `agent-usage@local/applet.js` | The applet in the panel, its popup, its settings and clicks |
| `agent-usage@local/settings-schema.json`, `metadata.json`, `stylesheet.css`, `icon.png` | Cinnamon's settings window, the applet's details, Cinnamon's additions to the stylesheet, the icon in System Settings |
| `build-applet.sh` | Builds the applet: those files, the collectors, session hooks and icons, the shared stylesheet, and the shared modules rewritten for Cinnamon |
| `esm-to-cinnamon.py` | Rewrites a shared module (an ES module) into the form Cinnamon loads |
| `install.sh`, `uninstall.sh`, `diagnose.sh` | Install, remove and debug the applet |
| `cinnamon-state.py` | Asks the running Cinnamon whether the applet loaded, and for its log lines |
| `test/` | The smoke test in Linux Mint's Docker images |

The macOS app lives in `macos/` and bundles the same two collectors, and the
session hooks:

| Piece | What it does |
|---|---|
| `Sources/AgentUsageCore/` | Everything the panel decides without a screen, ported from `usage.js`, `sessions.js`, `updates.js`, `versions.js` and `terminals.js`. It also runs the collectors itself, since `agent-usage-update` needs bash 4 and a Mac has 3.2. Foundation only, so it builds and tests on Linux too |
| `Sources/AgentUsage/` | The menu bar item, the panel (SwiftUI), the settings window, the timers, the update check, start at login |
| `Resources/` | `Info.plist`, the icons as PDFs and JetBrains Mono |
| `build-app.sh` | Builds `Agent Usage.app`: universal, signed ad hoc, with the collectors from `agent-usage@local/bin` and the session hooks from `agent-usage@local/hooks` |
| `agent-usage` | The Mac's `agent-usage` command, inside the app |
| `Tests/`, `test/` | The Swift tests, and the Mac's install, update and uninstall test |

The folders keep Omarchy's names (`~/.local/state/omarchy/…` and
`~/.cache/omarchy/agent-usage/`). That way the collectors stay as close to
Omarchy's as possible: every change is a patch file in `patches/`.

### OpenCode v2 fixes

Omarchy 4.0.4's collectors only read OpenCode's old `message` table. OpenCode
v2 stores messages in `session_message`, so its usage was never counted
([omacom/omarchy#13893](https://github.com/omacom/omarchy/issues/13893)).
These collectors are Omarchy 4.0.4 with two open upstream fixes applied.
Both are in `patches/`:

| Collector | Fix | Commit |
|---|---|---|
| `agent-usage-claude` | [#13894](https://github.com/omacom/omarchy/pull/13894): Count Claude usage from opencode v2 sessions | `db4daae` |
| `agent-usage-codex` | [#7686](https://github.com/omacom/omarchy/pull/7686): Include OpenCode v2 sessions, and only count the last 30 days of OpenCode usage | `48a7927` |

On top of that, both collectors have changes of their own, which aren't
from upstream:

- `patches/claude-limits-backoff.diff` adds the rate-limit back-off and the
  stale marking described under [Refreshing](#refreshing).
- `patches/claude-macos-keychain.diff` is for the macOS app. On a Mac,
  Claude Code keeps its login in the Keychain rather than in
  `~/.claude/.credentials.json`, so this reads it from there. On Linux it
  changes nothing.
- `patches/claude-sign-in-refused.diff`: when Anthropic refuses the saved
  sign-in (401 or 403), the record says *Sign-in expired*, so the problem
  card offers the fix. Before, this was a generic error, hidden whenever
  there were cached limits to show.
- `patches/codex-sign-in.diff`: when Codex isn't signed in, the record says
  *Not signed in*. Before, it said nothing at all.

When those PRs are merged:

- **Codex:** take the official collector **and reapply**
  `codex-sign-in.diff`:
  ```bash
  cd ~/.local/share/gnome-shell/extensions/agent-usage@local/bin
  curl -fsSL https://raw.githubusercontent.com/omacom/omarchy/master/bin/omarchy-agent-usage-codex -o agent-usage-codex
  patch agent-usage-codex < /path/to/agent-usage/patches/codex-sign-in.diff
  chmod +x agent-usage-codex
  ```
- **Claude:** take the official collector **and reapply**
  `claude-limits-backoff.diff`, `claude-macos-keychain.diff` and
  `claude-sign-in-refused.diff`, in that order. Without them, the back-off,
  the stale marking, the Mac sign-in and the refused sign-in are gone:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/omacom/omarchy/master/bin/omarchy-agent-usage-claude -o agent-usage-claude
  patch agent-usage-claude < /path/to/agent-usage/patches/claude-limits-backoff.diff
  patch agent-usage-claude < /path/to/agent-usage/patches/claude-macos-keychain.diff
  patch agent-usage-claude < /path/to/agent-usage/patches/claude-sign-in-refused.diff
  chmod +x agent-usage-claude
  ```

Usage from OpenCode's own models (OpenCode Zen/Go, such as `big-pickle`)
isn't counted by either collector.

## Releasing

1. Add a `## X.Y.Z` section to `CHANGELOG.md`.
2. Run `scripts/release.sh X.Y.Z`.

The script:

- refuses unless you're on a clean `main`;
- runs every test;
- writes `VERSION`, commits, tags `vX.Y.Z` and pushes;
- creates the GitHub release with that changelog section as its notes.

GitHub Actions runs the same tests on every push, plus the smoke tests in
real shells, and checks that a release tag matches `VERSION`. On a release tag it also builds the macOS app and
attaches `Agent-Usage-macOS.zip` to the release, which is what `get.sh`
installs on a Mac. Installs see the release the next time someone runs
`agent-usage update`, or the next time their panel checks.

Tests without GNOME or Cinnamon:

```bash
for t in test/*-test.js; do gjs -m "$t"; done   # panel logic, the modules and settings for Cinnamon
python3 test/claude-limits-test.py              # Claude limits back-off, refused sign-in
python3 test/claude-keychain-test.py            # Claude sign-in from the macOS Keychain
python3 test/codex-sign-in-test.py              # Codex signed out, with a fake app server
python3 test/session-hooks-test.py              # the session colors' hook, and adding it to Claude Code and OpenCode
node test/opencode-plugin-test.mjs              # the OpenCode plugin, with a stand-in OpenCode
test/cli-test.sh                                # install, update, uninstall from git, on GNOME and Mint
(cd macos && swift test)                        # the macOS app's logic, on Linux too
```

Smoke tests in real shells, with Docker. Each installs the panel, fills it
from a stand-in collector, clicks through it from inside the shell, and saves
screenshots under `test/gnome/snapshots/` or `cinnamon/snapshots/`:

```bash
test/gnome/run-in-ubuntu.sh 24.04               # headless GNOME Shell 46 (26.04: GNOME 50)
cinnamon/test/run-in-mint.sh mint22.3           # Cinnamon 6.6 (mint21.3: 6.0; mint22.3-loader6.8: 6.8's applet loading)
```

The first run of each installs the shell into an image and keeps it, so
later runs take seconds. See [0030](docs/adr/0030-testing-in-real-shells.md).

On every push and pull request, GitHub also runs the smoke tests: GNOME 46
and 50, and Mint 21.3, 22.3 and 22.3 with Cinnamon 6.8's applet loading. The
screenshots are kept as artifacts.

A macOS job on GitHub also:
- builds the app;
- draws the panel to PNGs, kept as the `snapshots` artifact;
- starts the app and waits for the collectors' records;
- runs `macos/test/cli-test.sh` to install, update and uninstall it.

See [0022](docs/adr/0022-testing-the-macos-app.md).

## License

The collectors come from [Omarchy](https://github.com/omacom/omarchy), and
the panel is a port of Omarchy's `omarchy.agents` widget. Both are under
Omarchy's MIT license (see `LICENSE`). The Claude and Codex logos belong to
their owners. The macOS app bundles JetBrains Mono, under the SIL Open Font
License (`macos/Resources/Fonts/OFL.txt`).
