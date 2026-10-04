# 0023. Desktop apps, and sign-in buttons in the problem card

- Status: Accepted
- Date: 2026-10-04

## Context

The maintainer asked for two things on top of
[0012](0012-configurable-agent-and-terminal.md) and
[0020](0020-opening-the-agent-on-macos.md):

- **Desktop apps:** the open button always starts an agent in a terminal.
  Some people use the desktop app of Claude Code or OpenCode instead.
  - **Claude:** `Claude.app` on a Mac. On Linux, `claude-desktop` from
    Anthropic's apt repository, a beta for Ubuntu and Debian since June
    2026.
  - **OpenCode:** `OpenCode.app` on a Mac. On Linux, a `.deb`, `.rpm` or
    AppImage, with the app id `ai.opencode.desktop`.
  - **Codex:** OpenAI stopped its separate Codex app; it's part of the
    ChatGPT app now.
- **Signing in again:** Claude Code's saved sign-in runs out when Claude
  Code hasn't run for a while. The panel then says *Sign-in expired*, and
  the fix is to start Claude Code or run `claude auth login`, by hand, in a
  terminal.
- **Two gaps in the collectors:**
  - **A refused sign-in** (HTTP 401 or 403 from Anthropic's usage
    endpoint, e.g. after signing in elsewhere) was a generic *Claude limits
    unavailable*. With cached limits to show, there was no card at all.
  - **Codex signed out** showed nothing. Its app server answers
    `account/read` with `account: null, requiresOpenaiAuth: true` instead of
    an error, and the collector took that as "no limits".

## Decision

**Desktop apps are agents:**
- **Two more entries under *Agent*:** *OpenCode (desktop app)* and
  *Claude (desktop app)*, ids `opencode-desktop` and `claude-desktop`. One
  setting still decides what the button and right-click open.
- **Finding them on GNOME:**
  - **Desktop file:** `ai.opencode.desktop.desktop` (or the older
    `opencode-desktop.desktop`), `claude-desktop.desktop`.
  - **Any desktop file that runs the app's program:** `ai.opencode.desktop`,
    `opencode-desktop`, `claude-desktop`.
  - **The program itself,** such as `~/Applications/OpenCode.AppImage`.
- **Finding them on a Mac:** by bundle id
  (`ai.opencode.desktop`, `com.anthropic.claudefordesktop`), then in the
  Applications folders, like the terminals.
- **Opening them:** on GNOME through the Shell's app system, which brings
  an open app to the front. On a Mac, `open -a`.
- **The button:** an app icon instead of the terminal icon, and the hint
  says *Open Claude (desktop app)*. Missing, the button hides, as for a
  missing agent.

**Sign-in buttons in the problem card:**
- **When:** only when the record's status is a sign-in problem.
  - **Claude:** *Waiting for auth* or *Sign-in expired*. The buttons are
    **Start Claude Code** (`claude`, which refreshes the saved sign-in) and
    **Sign in** (`claude auth login`).
  - **Codex:** *Not signed in*. The button is **Sign in** (`codex login`).
- **Always in the terminal:** the chosen terminal, as for the Update
  button, even when *Agent* is a desktop app. The desktop apps keep their own
  sign-in, which isn't the one the collectors read.
- **Readable outcome:** **Sign in** runs through `sh -c` with a pause, so
  the window waits for Enter instead of closing on the last line.
- **Catching up:** after a click, the panel checks that agent's limits every
  15 seconds, at most 20 times, and stops as soon as the problem is gone.
  While Claude's saved sign-in is expired or missing, a check doesn't reach
  Anthropic at all.
- **Shared logic:** which statuses get which buttons is in `usage.js` and
  `Usage.swift`; the terminal command is in `terminals.js` and
  `Terminals.swift`.

**Two collector patches of our own**
([0005](0005-collector-changes-as-patches.md)):
- **`claude-sign-in-refused.diff`:** a 401 or 403 becomes *Sign-in expired*,
  with the same advice as an expired sign-in, and the last limits stay on
  screen, marked stale.
- **`codex-sign-in.diff`:** no account where one is required becomes *Not
  signed in*, with `codex login` as the advice.

## Alternatives

- **A separate *Open in: Terminal / Desktop app* setting:** two settings
  for one choice, and the desktop app would need a per-agent mapping.
- **A second button for the desktop app:** a crowded header, and
  right-click could still only do one of them.
- **Always a sign-in button in the header:** it's only useful when something
  is wrong, and the problem card is where that's said.
- **Refreshing Claude's token ourselves:** the collector could use the
  saved refresh token, but writing Claude Code's login (or Keychain entry)
  behind its back risks signing it out.

## Consequences

- **The settings schema lists the new agent ids.** The test that checks
  them against `terminals.js` covers it.
- **Not yet confirmed on a real machine:**
  - the official Linux Claude package's desktop file name (the program
    name, `claude-desktop`, is documented);
  - the Mac bundle ids, which come from Homebrew's casks.
- **A refused sign-in is checked for real:** until it's fixed, each of
  those checks asks Anthropic and gets a 401. Should that run into a 429,
  the back-off of [0008](0008-rate-limit-back-off-and-stale-limits.md)
  applies and the checks stop early. The regular checks pick it up later.
- **Codex** shows its card only when it has usage to show, like any agent.
  A Codex install that was never used stays out of the panel.
