# Agent Usage for GNOME

Omarchy's **Agents** panel as a GNOME Shell extension, in Omarchy's Kanagawa
look. It shows Claude Code and Codex rate limits with reset countdowns, plus
tokens by day and by model. That includes sessions you ran in **OpenCode v2**.

- **Top bar:** a robot icon with your fullest limit (`61%`). It turns red at
  90% or more. It stays hidden until an agent has usage to show.
- **Panel:**
  - **Header:** the agent's logo, name and plan, with refresh, *Open agent*
    and ⚙ settings buttons.
  - **Tabs:** one per agent, if you have more than one.
  - **Problem card:** shows up when something needs fixing (sign-in,
    missing CLI).
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
  opens your agent (OpenCode by default) in a terminal.
- **Keyboard (panel open):** ←/→ (or h/l) switches agent, `r` refreshes,
  Esc closes.

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

The panel's terminal button, and right-clicking the top-bar icon, open an
agent in a terminal. Both are set in the same settings window, under *Open
agent*:

- **Agent:** OpenCode (the default), Claude Code, Codex, or *Custom…*.
  Custom takes any command, e.g. `claude --continue`. Agents that aren't
  installed are marked.
- **Terminal:** *Automatic* (the default) uses the desktop's default
  terminal, which is GNOME Terminal on stock Ubuntu. Or pick one of the
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

Made for GNOME 46 (Ubuntu 24.04) and up.

## Install

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

The panel checks once a day. When a new version is out, its bottom line says
*v0.6.1 available*. Clicking that opens ⚙, where **Update** runs
`agent-usage update` in your terminal. The daily check can be switched off
there.

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

## When something looks wrong

Run `agent-usage diagnose` (or `./diagnose.sh`) and paste its output. It shows the GNOME version, whether
the extension loaded or failed, the usage records and the extension's lines
from the GNOME Shell log.

## How it works

| Piece | What it does |
|---|---|
The extension lives in `agent-usage@local/`:

| Piece | What it does |
|---|---|
| `bin/agent-usage-claude` | Claude Code limits (Anthropic's usage endpoint) and token stats. The stats come from `~/.claude/projects` plus OpenCode sessions on the `anthropic` provider |
| `bin/agent-usage-codex` | Codex limits (`codex app-server`) and token stats. The stats come from Codex sessions plus OpenCode sessions on the `openai` provider |
| `bin/agent-usage-update` | Runs the collectors and writes one JSON file per agent to `~/.local/state/omarchy/agents/usage/`. It's also on your PATH, so `agent-usage-update --force` collects again by hand |
| `extension.js`, `usage.js`, `updates.js`, `stylesheet.css` | The top-bar button and panel. They schedule the updater and display those JSON files |
| `terminals.js` | Which agent to open and how to start each terminal. The panel and the settings window both use it |
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

The Claude collector has one more change of its own on top of that, which
isn't from upstream: `patches/claude-limits-backoff.diff`. It adds the
rate-limit back-off and the stale marking described under
[Refreshing](#refreshing).

When those PRs are merged:

- **Codex:** switch to the official collector:
  ```bash
  cd ~/.local/share/gnome-shell/extensions/agent-usage@local/bin
  curl -fsSL https://raw.githubusercontent.com/omacom/omarchy/master/bin/omarchy-agent-usage-codex -o agent-usage-codex
  chmod +x agent-usage-codex
  ```
- **Claude:** take the official collector **and reapply**
  `claude-limits-backoff.diff`. Without it, the back-off and stale marking
  are gone:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/omacom/omarchy/master/bin/omarchy-agent-usage-claude -o agent-usage-claude
  patch agent-usage-claude < /path/to/agent-usage/patches/claude-limits-backoff.diff
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
tag matches `VERSION`. Installs see the release the next time someone runs
`agent-usage update`, or the next time their panel checks.

Tests, all without GNOME:

```bash
for t in test/*-test.js; do gjs -m "$t"; done   # panel logic
python3 test/claude-limits-test.py              # Claude limits back-off
test/cli-test.sh                                # install, update, uninstall from git
```

## License

The collectors come from [Omarchy](https://github.com/omacom/omarchy), and
the panel is a port of Omarchy's `omarchy.agents` widget. Both are under
Omarchy's MIT license (see `LICENSE`). The Claude and Codex logos belong to
their owners.
