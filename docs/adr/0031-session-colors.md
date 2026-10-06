# 0031. Session colors: the robot says when an agent wants you

- Status: Accepted
- Date: 2026-10-06

## Context

The panel showed limits and tokens, but not what the agents were doing. With
Claude Code or OpenCode running in a terminal behind other windows, there was
no way to see from the top bar that a session had finished, or that it was
stuck on a permission prompt.

Both agents can tell:

- **Claude Code** runs hooks, commands from its settings, at points in a
  session: `UserPromptSubmit`, `Stop`, `PermissionRequest`, and so on. Each
  gets the event as JSON on stdin.
- **OpenCode 2** loads plugins from `~/.config/opencode/plugins/`. A plugin
  can follow the server's event stream: `session.execution.started` and
  `.succeeded`, `permission.asked` and `.replied`, `form.created` (a
  question) and more. OpenCode's own terminal UI uses the same events to show
  *awaiting permission*.

Trying them out on OpenCode 2.0.22 and Claude Code 2.1.285 settled the
details:

- **OpenCode** starts a global plugin once for every folder it works in, all
  in one process. Each instance sees every session's events, not only its
  own folder's.
- **A plugin with a plain default export** (`{id, setup}`) loads without
  importing `@opencode/plugin`, so nothing has to be installed for it.
- **A Claude Code hook's parent process is `claude`,** also through `sh -c`,
  which hands over to a single command.
- **A background (`async`) `Stop` hook can be cut off** when `claude -p`
  exits right after it.

## Decision

- **Two colors on the robot:**
  - **orange** while any session waits for you: a permission prompt, a
    question, a plan to approve, an MCP server asking for input;
  - **green** when a session has finished its turn and you haven't looked
    since.

  Otherwise the robot keeps its usual color. Kanagawa's `#ffa066` and
  `#98bb6c`, distinct from the stale yellow and the urgent red.
- **Green clears when you look:** opening the panel, or right-clicking to
  open your agent, writes the time to `.seen`. Turns that finished before it
  no longer count. Orange can't be cleared that way; it goes when the session
  moves on.
- **Red stays with the number:** at 90% or more the percentage is red as
  before. The robot only turns red when no session wants anything.
- **One file per session** in `~/.local/state/omarchy/agents/sessions/`:
  agent, session, state (`idle`, `working`, `waiting`, `ready`), since when,
  last written, the agent's pid and its folder. The panel watches the folder
  as it watches the usage records.
  - **Left out:** a session whose pid isn't running (a closed terminal), and
    one nobody touched for a day.
  - **Subagents** only count while they wait for you: a subagent finishing
    isn't your turn.
  - The rules are in `sessions.js`, shared by GNOME and Cinnamon, and its
    Swift port `Sessions.swift`.
- **Claude Code:** `hooks/agent-usage-session`, a Python script, is the hook
  for every event, and writes the file:

  | State | Events |
  |---|---|
  | idle | `SessionStart` |
  | working | `UserPromptSubmit`; `PostToolUse`, `PostToolUseFailure`, `ElicitationResult` end a wait |
  | waiting | `PermissionRequest`, `Elicitation`, `PreToolUse` for `AskUserQuestion` and `ExitPlanMode` |
  | ready | `Stop`, `StopFailure` |
  | gone | `SessionEnd` removes the file |

  - **Only the agent that waits ends the wait:** a subagent's tool finishing
    doesn't answer the main agent's permission prompt.
  - **The turn's edges run in the foreground:** a few hundredths of a second
    each. Only the tool events, which fire after every tool call, run in the
    background.
  - **Shell form, with the Python that installed them:** the hooks run
    `<python> ~/.local/bin/agent-usage-session hook claude`. The shell form
    works in every Claude Code version (exec form with `args` doesn't).
    Naming the Python avoids the script's `#!/usr/bin/python3`, which opens
    an install dialog on a Mac without Apple's Command Line Tools.
- **OpenCode 2:** `hooks/opencode-agent-usage.js`, copied to
  `~/.config/opencode/plugins/agent-usage.js`.
  - **One writer:** the instances share a registry on `globalThis`. One
    follows the event stream; the others stand by and take over if it
    unloads. With every instance writing, one that lags could put an older
    state back.
  - **In order:** events are handled synchronously. Only looking up a
    session that started before the plugin (its folder, whether it's a
    subagent's) waits for OpenCode.
  - **Interrupting a turn yourself** makes the session idle rather than
    ready: you're already there.
- **`install`, `uninstall` and `status`** live in the same script:
  - **Claude Code:** the hooks go into `~/.claude/settings.json` (or
    `$CLAUDE_CONFIG_DIR`), after the ones already there. They're recognised
    by `agent-usage-session` in the command, so uninstalling takes out only
    those. Nothing is written when nothing changes; a file that isn't valid
    JSON is left alone; a settings file linked from elsewhere stays a link,
    with its permissions.
  - **OpenCode:** the plugin only goes in for OpenCode 2. OpenCode 1 loads
    plugins differently and would trip over it.
  - **Only agents that are there:** no `~/.claude` folder, or no `opencode`,
    means nothing is added for it.
- **When they're added:** by the installer and every update, which say so,
  and by the panel each time it starts, so an agent installed later gets them
  too.
- **A setting, on by default:** *Session colors* (`session-colors`,
  `sessionColors` on a Mac). Switching it off removes the hooks and the
  plugin; the installer and the panel then leave them out. `agent-usage
  uninstall` removes them as well.
- **Outside `bin/`:** the script and the plugin live in `hooks/`. Everything
  in `bin/` named `agent-usage-*` is run as a collector, by
  `agent-usage-update` and by the Mac app alike.

## Alternatives

- **Green while any session is idle:** the robot would be green nearly all
  the time, since a session stays idle until you type again.
- **Green for a few minutes:** it would go away while you're elsewhere,
  which is when it's useful.
- **The session color on the percentage too:** a limit at 95% would then go
  unnoticed while a session waits.
- **Claude Code's `Notification` hook** (`permission_prompt`) for orange: it
  can come after you've already answered. `PermissionRequest` comes before
  the prompt shows.
- **Every OpenCode instance writing:** harmless for duplicates, but one
  lagging behind can write an older state last.
- **A separate opt-in command:** the colors wouldn't work for anyone who
  didn't read the README. The setting is the way out instead.
- **A Claude Code plugin** for the hooks: it needs a marketplace to install
  from, and still a settings change to enable it.

## Consequences

- **The installer edits other programs' settings.** It says so, and the
  setting takes the changes out again.
- **No hook for approving a permission** in Claude Code: after you approve,
  the robot stays orange until that tool finishes.
- **GNOME shows the colors only after it reloads** the extension (log out
  and in on Wayland), as with any update. The hooks work right away.
- **Tests:** `test/sessions-test.js` and `SessionsTests.swift` (the rules),
  `test/session-hooks-test.py` (the hook and installing it),
  `test/opencode-plugin-test.mjs` (the plugin, with a stand-in OpenCode),
  `test/cli-test.sh` (install and uninstall through `get.sh`), and the
  smoke tests in real shells read the robot's color and take screenshots of
  it.
