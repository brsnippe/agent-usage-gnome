# 0012. The agent and terminal to open are settings

- Status: Accepted
- Date: 2026-10-02

## Context

The panel's terminal button, and right-clicking the top-bar icon, open
OpenCode. At first they used the first terminal found from a fixed list
(`xdg-terminal-exec`, Ptyxis, GNOME Terminal, `x-terminal-emulator`). On
stock Ubuntu 24.04 that means GNOME Terminal. The maintainer uses Ghostty,
and other people use other agents.

## Decision

**Two settings, in a new *Open agent* group of the settings window:**

- **Agent:** OpenCode (the default), Claude Code, Codex, or a custom command
  (e.g. `claude --continue`). Agents that aren't installed are marked.
- **Terminal:**
  - **Automatic** (the default): the old behaviour, so nothing changes
    unless someone picks something.
  - **One of nine known terminals,** each with its own command line:
    Ghostty `-e`, GNOME Terminal `--`, Ptyxis `--new-window -x`, Kitty,
    Alacritty `-e`, WezTerm `start --`, Foot, Konsole `-e`, xterm `-e`. The
    dropdown lists only those that are installed.
  - **Custom:** a template where `{command}` marks where the agent goes.
    Without `{command}`, the agent goes at the end. Inside a longer argument,
    it becomes one quoted string.

**Finding programs:** agents and terminals are looked up on the PATH, plus
`~/.local/bin`, `~/.opencode/bin`, `~/.npm-global/bin`, `~/.bun/bin`,
`~/.cargo/bin`, mise's shims and `/snap/bin`. GNOME Shell's PATH often lacks
the per-user folders.

**No silent fallback:** if the chosen terminal goes missing, a notification
says so. Opening a different one instead would be surprising.

**Try it:** a row in the settings window shows the exact command that will
run, and its *Open* button runs it.

**One shared module:** `terminals.js` builds the command lines for both the
panel and the settings window, so *Try it* behaves exactly like the button.

## Alternatives

- **Only fix the terminal** (e.g. always Ghostty): no good for anyone else.
- **Rely on `x-terminal-emulator` alone:** Debian's choice, which doesn't
  follow the user's preference on GNOME.

## Consequences

- **The settings schema lists the allowed values.** A test checks that they
  match `terminals.js`.
- **The Update button reuses the terminal choice**
  ([0016](0016-versions-releases-and-update-check.md)).
- **On macOS, the same settings open Mac terminals**
  ([0020](0020-opening-the-agent-on-macos.md)).
- **Desktop apps joined the agent list later,** and the sign-in buttons use
  the terminal choice too ([0023](0023-desktop-apps-and-sign-in-buttons.md)).
