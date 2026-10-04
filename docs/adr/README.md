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
| [0017](0017-testing-without-gnome-shell.md) | Test without GNOME Shell | Accepted |
| [0018](0018-native-macos-app.md) | A native macOS menu bar app | Accepted |
| [0019](0019-claude-login-from-the-macos-keychain.md) | Read Claude Code's login from the macOS Keychain | Accepted |
| [0020](0020-opening-the-agent-on-macos.md) | Opening the agent on macOS | Accepted |
| [0021](0021-install-on-macos-from-the-release-zip.md) | Install on macOS from the release zip | Accepted |
| [0022](0022-testing-the-macos-app.md) | Test the macOS app without a Mac | Accepted |

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
- **The panel's font:** the stylesheet asks for JetBrains Mono, but on Ubuntu
  the panel renders in the system font. That was left as is.
- **No `scripts/sync-upstream.sh`.** A script to fetch Omarchy's latest
  collectors and reapply the patches was considered but not built.
- **The Mac app hasn't run on a coworker's Mac yet.** What the trial has to
  confirm:
  - iTerm2 and the `open -na` terminals ([0020](0020-opening-the-agent-on-macos.md));
  - a possible Keychain prompt ([0019](0019-claude-login-from-the-macos-keychain.md));
  - start at login with an ad-hoc signed app
    ([0021](0021-install-on-macos-from-the-release-zip.md));
  - the panel window's behaviour.
- **The Mac app isn't notarized.** Browser downloads need the `xattr` line
  until there's an Apple Developer account
  ([0021](0021-install-on-macos-from-the-release-zip.md)).
- **Two implementations of the panel's logic:** `usage.js` and the Swift
  port ([0018](0018-native-macos-app.md)).
