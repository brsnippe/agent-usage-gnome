# Agent Usage for GNOME and macOS

Omarchy's **Agents** panel as a GNOME Shell extension, in Omarchy's Kanagawa
look. It shows Claude Code and Codex rate limits with reset countdowns, plus
tokens by day and by model. That includes sessions you ran in **OpenCode v2**.

On a Mac it's the same panel under a menu bar icon: see [macOS](#macos).

- **Top bar:** a robot icon with your fullest limit (`61%`). It turns red at
  90% or more. It stays hidden until an agent has usage to show.
- **Panel:**
  - **Header:** the agent's logo, name and plan, with refresh, *Open agent*
    and ⚙ settings buttons.
  - **Tabs:** one per agent, if you have more than one.
  - **Problem card:** shows up when something needs fixing (sign-in,
    missing CLI). When the sign-in is the problem, its buttons fix it: see
    [Signing in again](#signing-in-again).
  - **Sections:**
    - **Limits** and **Tokens by day.**
    - **Today by model:** today's tokens per model, with each model's share of
      the day on hover.
    - **All time by model:** the top 4 models by all-time tokens, with the
      in/out/cache split on hover.

    All of them use real bars, and hovering a row shows details in the
    bottom line. On a small screen the panel scrolls rather than running off
    the bottom.
- **Mouse:** left-click opens the panel, middle-click refreshes, right-click
  opens your agent (OpenCode by default) in a terminal, or a desktop app.
- **Keyboard (panel open):** ←/→ (or h/l) switches agent, `r` refreshes,
  Esc closes.

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
agent-usage uninstall            # remove the app (--purge: also data, settings, logs)
```

### Where things are on a Mac

| What | Where |
|---|---|
| The app | `~/Applications/Agent Usage.app` |
| Usage records | `~/.local/state/omarchy/agents/usage/`, as on Linux |
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
  is locked, so nothing runs while you're away.

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

## Install

This and the next sections are about GNOME; on a Mac, see
[Install on a Mac](#install-on-a-mac).

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
- `agent-usage uninstall`: remove it. Add `--purge` to also delete the usage
  data and settings.

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
4. Collects usage once and prints what it found.

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
from the GNOME Shell log.

## How it works

Why it's built this way, decision by decision:
[docs/adr/](docs/adr/README.md).

The extension lives in `agent-usage@local/`:

| Piece | What it does |
|---|---|
| `bin/agent-usage-claude` | Claude Code limits (Anthropic's usage endpoint) and token stats. The stats come from `~/.claude/projects` plus OpenCode sessions on the `anthropic` provider |
| `bin/agent-usage-codex` | Codex limits (`codex app-server`) and token stats. The stats come from Codex sessions plus OpenCode sessions on the `openai` provider |
| `bin/agent-usage-update` | Runs the collectors and writes one JSON file per agent to `~/.local/state/omarchy/agents/usage/`. It's also on your PATH, so `agent-usage-update --force` collects again by hand |
| `extension.js`, `usage.js`, `updates.js`, `stylesheet.css` | The top-bar button and panel. They schedule the updater and display those JSON files |
| `terminals.js` | Which agent or desktop app to open, how to start each terminal, and the sign-in commands. The panel and the settings window both use it |
| `versions.js` | Compares release versions for the update notice |
| `prefs.js`, `schemas/` | The settings window and its settings: the refresh intervals, the agent, the terminal and update checks |

Around it, in the repository:

| Piece | What it does |
|---|---|
| `get.sh` | First install from git |
| `bin/agent-usage` | `update`, `version`, `latest`, `diagnose`, `uninstall` |
| `install.sh`, `uninstall.sh`, `diagnose.sh`, `preview.sh` | Install, remove, debug and preview the extension |
| `VERSION`, `CHANGELOG.md`, `scripts/release.sh` | Releases (see [Releasing](#releasing)) |
| `patches/`, `test/` | The changes to Omarchy's collectors, and the tests |
| `macos/` | The macOS app: see below |

The macOS app lives in `macos/` and bundles the same two collectors:

| Piece | What it does |
|---|---|
| `Sources/AgentUsageCore/` | Everything the panel decides without a screen, ported from `usage.js`, `updates.js`, `versions.js` and `terminals.js`. It also runs the collectors itself, since `agent-usage-update` needs bash 4 and a Mac has 3.2. Foundation only, so it builds and tests on Linux too |
| `Sources/AgentUsage/` | The menu bar item, the panel (SwiftUI), the settings window, the timers, the update check, start at login |
| `Resources/` | `Info.plist`, the icons as PDFs and JetBrains Mono |
| `build-app.sh` | Builds `Agent Usage.app`: universal, signed ad hoc, with the collectors from `agent-usage@local/bin` |
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

GitHub Actions runs the same tests on every push and checks that a release
tag matches `VERSION`. On a release tag it also builds the macOS app and
attaches `Agent-Usage-macOS.zip` to the release, which is what `get.sh`
installs on a Mac. Installs see the release the next time someone runs
`agent-usage update`, or the next time their panel checks.

Tests, all without GNOME:

```bash
for t in test/*-test.js; do gjs -m "$t"; done   # panel logic
python3 test/claude-limits-test.py              # Claude limits back-off, refused sign-in
python3 test/claude-keychain-test.py            # Claude sign-in from the macOS Keychain
python3 test/codex-sign-in-test.py              # Codex signed out, with a fake app server
test/cli-test.sh                                # install, update, uninstall from git
(cd macos && swift test)                        # the macOS app's logic, on Linux too
```

On every push and pull request, a macOS job on GitHub also:
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
