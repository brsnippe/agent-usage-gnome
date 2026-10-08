# Design decisions

Each file here records one decision: its context, what was decided, which
alternatives were considered, and what follows from it. Decisions that were
later replaced stay here, marked *Superseded*, so the reasoning behind the
current design isn't lost.

## Background

The project started on an [Omarchy](https://github.com/omacom/omarchy)
machine with a simple question: why had the AI agent icon disappeared from
Omarchy's top bar?

- **The icon:** Omarchy's Agents widget hides itself when it has nothing to
  show. Claude Code had been signed out, so there were no rate limits to
  display.
- **The bug:** looking into it turned up a real bug. Omarchy's usage
  collectors only read OpenCode's old `message` table, while OpenCode v2
  stores messages in `session_message`, so OpenCode v2 usage was never
  counted. This was reported upstream as
  [omacom/omarchy#13893](https://github.com/omacom/omarchy/issues/13893).
  Fixes followed as
  [#13894](https://github.com/omacom/omarchy/pull/13894) (Claude) and the
  already open [#7686](https://github.com/omacom/omarchy/pull/7686) (Codex).
- **The port:** the next step was the same widget on an Ubuntu GNOME laptop.

That port grew into this repository. It went through six hand-delivered
builds before becoming the first tagged release, v0.6.0.

Then coworkers with MacBooks wanted the same panel, which became a native
macOS menu bar app in `macos/` ([0018](0018-native-macos-app.md)), built and
tested without a Mac at hand ([0022](0022-testing-the-macos-app.md)).

Coworkers on Linux Mint came next. Mint's default desktop is Cinnamon, a
GNOME Shell fork, so the panel became a Cinnamon applet in `cinnamon/`
([0027](0027-cinnamon-applet-for-linux-mint.md)). It shares its code with the
GNOME extension ([0028](0028-shared-panel-code.md)). Both now run in real
shells in Docker ([0030](0030-testing-in-real-shells.md)).

## How it was built

It was built iteratively with an AI coding agent: Claude Opus 5.5, running in
[OpenCode](https://opencode.ai), on the Omarchy machine.

- **Plan, then build:** each change was first discussed in OpenCode's plan
  mode, where the agent may only read and propose. It was built once the
  maintainer agreed.
- **Testing in two places:** the agent tested what it could on the
  development machine (see [0017](0017-testing-without-gnome-shell.md)). The
  maintainer installed each build on the Ubuntu laptop and reported back what
  they saw, plus the output of `diagnose.sh` when something was off.
- **Findings changed the design:** several decisions below came straight out
  of those reports. Examples are Anthropic's rate limiting
  ([0008](0008-rate-limit-back-off-and-stale-limits.md)), the missing model
  ([0010](0010-model-sections.md)) and the X11 session
  ([0014](0014-reloading-gnome-shell.md)).

## Decisions

| # | Decision | Status |
|---|---|---|
| [0001](0001-port-omarchy-agents-widget.md) | Port Omarchy's Agents widget, reusing its collectors and data folders | Accepted |
| [0002](0002-tray-indicator.md) | Show it as a tray indicator | Superseded by 0003 |
| [0003](0003-gnome-shell-extension.md) | A GNOME Shell extension in Omarchy's Kanagawa look | Accepted |
| [0004](0004-count-opencode-v2-usage.md) | Count OpenCode v2 usage by applying the upstream fixes | Accepted |
| [0005](0005-collector-changes-as-patches.md) | Changes to Omarchy's collectors live only as patch files | Accepted |
| [0006](0006-refresh-timers-and-update-queue.md) | Two refresh timers and a ranked update queue | Accepted |
| [0007](0007-check-limits-every-15-seconds.md) | Check limits every 15 seconds | Superseded by 0008 |
| [0008](0008-rate-limit-back-off-and-stale-limits.md) | Back off on 429, mark stale limits, check every 5 minutes | Accepted |
| [0009](0009-details-in-the-footer.md) | Details in the footer instead of tooltips; scroll instead of overflow | Accepted |
| [0010](0010-model-sections.md) | All-time top 4 models, plus today by model | Accepted |
| [0011](0011-local-token-charts.md) | Limits are account-wide, token charts stay local, no sync | Accepted |
| [0012](0012-configurable-agent-and-terminal.md) | The agent and terminal to open are settings | Accepted |
| [0013](0013-extension-id.md) | Extension ID `agent-usage@local` | Accepted |
| [0014](0014-reloading-gnome-shell.md) | How GNOME Shell picks up new code | Accepted |
| [0015](0015-distribute-via-git.md) | Distribute via git with `get.sh` and the `agent-usage` command | Accepted |
| [0016](0016-versions-releases-and-update-check.md) | Versions, releases and the update check | Accepted |
| [0017](0017-testing-without-gnome-shell.md) | Test without GNOME Shell | Accepted, extended by 0030 |
| [0018](0018-native-macos-app.md) | A native macOS menu bar app | Accepted |
| [0019](0019-claude-login-from-the-macos-keychain.md) | Read Claude Code's login from the macOS Keychain | Accepted |
| [0020](0020-opening-the-agent-on-macos.md) | Opening the agent on macOS | Accepted |
| [0021](0021-install-on-macos-from-the-release-zip.md) | Install on macOS from the release zip | Accepted |
| [0022](0022-testing-the-macos-app.md) | Test the macOS app without a Mac | Accepted |
| [0023](0023-desktop-apps-and-sign-in-buttons.md) | Desktop apps as agents, and sign-in buttons in the problem card | Accepted |
| [0024](0024-check-for-releases-hourly.md) | Check for releases every hour, and after waking | Accepted |
| [0025](0025-session-limit-in-the-top-bar.md) | The top bar shows the session limit from 40% | Accepted |
| [0026](0026-all-time-total.md) | The all-time token total in the All time heading | Accepted |
| [0027](0027-cinnamon-applet-for-linux-mint.md) | A Cinnamon applet for Linux Mint | Accepted, extended by 0033 |
| [0028](0028-shared-panel-code.md) | One panel for GNOME and Cinnamon | Accepted |
| [0029](0029-installing-on-cinnamon.md) | Installing on Cinnamon, without logging out | Accepted |
| [0030](0030-testing-in-real-shells.md) | Test the panels in real shells, in Docker | Accepted, extended by 0033 |
| [0031](0031-session-colors.md) | Session colors: the robot says when an agent wants you | Accepted, extended by 0034 |
| [0032](0032-switching-it-off.md) | Switching it off: ⏻ in the panel | Accepted |
| [0033](0033-right-click-setting.md) | Right-click opening the agent is a setting | Accepted |
| [0034](0034-pop-and-sounds.md) | The robot pops and sounds when a session wants you | Accepted |
| [0035](0035-menu-bar-colors-follow-the-bar.md) | The Mac's menu bar colours follow the bar they're drawn on | Accepted |

## Open items

- **OpenCode Zen and Go usage isn't counted.** That's usage on OpenCode's own
  providers, e.g. free models like `big-pickle`. Omarchy has separate PRs for
  an OpenCode collector.
- **The upstream fixes aren't merged yet.** Once #13894 and #7686 are in
  Omarchy, switch to Omarchy's collectors. Reapply this project's own patches
  to the Claude collector ([0005](0005-collector-changes-as-patches.md)).
- **The rate-limit back-off hasn't been offered upstream.** Omarchy's widget
  checks only every 15 minutes, so it rarely meets the problem, but the
  silent fallback is still there ([0008](0008-rate-limit-back-off-and-stale-limits.md)).
- **No cross-machine sync of the token charts**
  ([0011](0011-local-token-charts.md)).
- **No `scripts/sync-upstream.sh`.** A script to fetch Omarchy's latest
  collectors and reapply the patches was considered but not built.
- **The Mac app hasn't run on a coworker's Mac yet.** What the trial has to
  confirm:
  - iTerm2 and the `open -na` terminals ([0020](0020-opening-the-agent-on-macos.md));
  - a possible Keychain prompt ([0019](0019-claude-login-from-the-macos-keychain.md));
  - start at login with an ad-hoc signed app
    ([0021](0021-install-on-macos-from-the-release-zip.md));
  - the panel window's behaviour.
- **The desktop apps haven't been tried on a coworker's machine yet:**
  the Linux Claude package's desktop file name, and the Mac bundle ids
  ([0023](0023-desktop-apps-and-sign-in-buttons.md)).
- **The Mac app isn't notarized.** Browser downloads need the `xattr` line
  until there's an Apple Developer account
  ([0021](0021-install-on-macos-from-the-release-zip.md)).
- **Two implementations of the panel's logic:** the JavaScript that GNOME
  and Cinnamon share, and the Swift port ([0018](0018-native-macos-app.md),
  [0028](0028-shared-panel-code.md)).
- **The Cinnamon applet hasn't run on a coworker's Mint yet.** The containers
  ([0030](0030-testing-in-real-shells.md)) can't show:
  - real clicks and keys, ←/→ in the open panel included;
  - Mint's themes, light and dark, around the panel;
  - pausing while the screen is locked, and waking from sleep;
  - the Update button end to end, and the terminal from Preferred
    Applications.
- **Mint 23 (Cinnamon 6.8)** is only tested with 6.8's applet loading on top
  of 6.6, until its images can install it
  ([0030](0030-testing-in-real-shells.md)).
- **Mint's MATE and Xfce editions** aren't covered
  ([0027](0027-cinnamon-applet-for-linux-mint.md)).
- **The session colors haven't run on a coworker's machine yet**
  ([0031](0031-session-colors.md)). What the trial has to confirm:
  - a whole day of real sessions, several at once, subagents included;
  - Claude Code in Claude's desktop app, and OpenCode's desktop app;
  - the hooks on a Mac, with the Command Line Tools' Python.
- **Codex** has no session colors ([0031](0031-session-colors.md)).
- **⏻ hasn't been clicked on a coworker's machine yet**
  ([0032](0032-switching-it-off.md)). The containers click it with a
  signal; a real click, the notification on screen, and getting it back
  through the Extensions app or Mint's Applets list are still to be seen.
  The Mac's ⏻ has only been drawn, in the snapshots.
- **The Mac's right-click switch has only been built in CI**
  ([0033](0033-right-click-setting.md)): a real right-click and
  Control-click with it off are still to be seen.
- **The pop and the sounds haven't run on a coworker's machine yet**
  ([0034](0034-pop-and-sounds.md)). What the trial has to confirm:
  - both sounds at a real volume, through a desktop's sound settings;
  - the pop on a real panel, at the panel's own height;
  - the Mac's pop, which only CI has run, inside a real menu bar.
- **The Mac's light-bar colours haven't been seen on a light menu bar yet**
  ([0035](0035-menu-bar-colors-follow-the-bar.md)): the lotus orange and
  green robot, and the black fade. The trial ran on a dark bar, on two
  screens.
