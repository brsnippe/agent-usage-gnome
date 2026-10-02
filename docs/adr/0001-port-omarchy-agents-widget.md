# 0001. Port Omarchy's Agents widget, reusing its collectors and data folders

- Status: Accepted
- Date: 2026-10-02

## Context

Omarchy 4.0.4's Agents widget shows Claude Code, Codex and Fireworks rate
limits and token usage in the top bar. It has two separate halves:

- **Collectors** (`omarchy-agent-usage-claude`, `-codex`, `-fireworks`):
  Python scripts using only the standard library, plus a bash wrapper,
  `omarchy-agent-usage-update`. Each prints one JSON record per agent, and
  the wrapper writes them to `~/.local/state/omarchy/agents/usage/`.
- **The display:** a Quickshell (QML) widget that watches those files. It
  depends on Omarchy's shell components and on a compositor with layer-shell
  support. Ubuntu's GNOME (Mutter) has neither.

The goal was the same information on an Ubuntu GNOME laptop.

## Decision

- **Reuse the collectors** almost unchanged. Only the wrapper changes: it
  finds the collectors next to itself instead of in Omarchy's install
  folder.
- **Rebuild the display** for GNOME ([0002](0002-tray-indicator.md), then
  [0003](0003-gnome-shell-extension.md)).
- **Leave Fireworks out:** it wasn't in use.
- **Keep Omarchy's folder names** (`~/.local/state/omarchy/…`,
  `~/.cache/omarchy/agent-usage/`) and Omarchy's record format. That keeps the
  collectors identical to upstream, and records from either system mean the
  same thing.

## Alternatives

- **Rewrite the collectors.** That would duplicate a lot of careful work
  (transcript scanning, caching, the OAuth limits probe, the Codex RPC) and
  lose easy updates from upstream.
- **Run Quickshell on GNOME.** It needs layer-shell, which Mutter doesn't
  offer, and the widget depends on Omarchy's own shell components.

## Consequences

- On Ubuntu, the data lives in folders named after Omarchy. The README
  explains why.
- On an Omarchy machine those folders belong to Omarchy's own widget. So
  `uninstall.sh --purge` refuses to delete them when `/usr/share/omarchy`
  exists.
- The collectors are MIT-licensed. `LICENSE` keeps Omarchy's notice.
- Upstream improvements can be taken over, as long as this project's changes
  stay separate ([0005](0005-collector-changes-as-patches.md)).
