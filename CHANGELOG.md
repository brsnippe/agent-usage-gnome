# Changelog

Versions are git tags (`v0.6.0`, …). `agent-usage update` installs the newest
one.

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
