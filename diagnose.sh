#!/bin/bash
# Print what's needed to debug the extension. Paste the output when
# something looks wrong.

UUID="agent-usage@local"
EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$UUID"
USAGE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/agents/usage"

echo "== GNOME"
gnome-shell --version
echo "session: ${XDG_SESSION_TYPE:-?} ${XDG_CURRENT_DESKTOP:-?}"

echo
echo "== Extension"
echo "installed: $([[ -f $EXT_DIR/metadata.json ]] && echo "yes, version $(jq -r '.["version-name"] // "build \(.version)"' "$EXT_DIR/metadata.json" 2>/dev/null)" || echo "no ($EXT_DIR is missing; run ./install.sh)")"
if [[ -f $EXT_DIR/source ]]; then
  source_dir=$(cat "$EXT_DIR/source")
  echo "source: $source_dir ($(git -C "$source_dir" remote get-url origin 2>/dev/null || echo "no remote"))"
  echo "newest release: $("$source_dir/bin/agent-usage" latest 2>&1)"
else
  echo "source: not a git install, so no updates"
fi
if info=$(LC_ALL=C gnome-extensions info "$UUID" 2>&1); then
  echo "$info"
else
  echo "loaded: no. GNOME hasn't picked it up since it was installed."
  if [[ ${XDG_SESSION_TYPE:-} == x11 ]]; then
    echo "  Fix: press Alt+F2, type r, press Enter (your windows stay open)."
  else
    echo "  Fix: log out and back in."
  fi
fi
echo "enabled-extensions: $(gsettings get org.gnome.shell enabled-extensions)"
for key in limits-interval scan-interval agent agent-command terminal terminal-command; do
  echo "$key: $(gsettings --schemadir "$EXT_DIR/schemas" get org.gnome.shell.extensions.agent-usage "$key" 2>&1)"
done

echo
echo "== Usage records"
ls -la "$USAGE_DIR" 2>&1
for record in "$USAGE_DIR"/*.json; do
  [[ -f $record ]] || continue
  jq -c '{id, ready, tierLabel, usageStatusText, limits: [.limits[]? | {label, title, percent}], limitsFetchedAt, limitsStale, limitsNote, totalPrompts, todayTotalTokens, updatedAt}' "$record" 2>&1
done

echo
echo "== Claude limits checks"
limits_cache="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/agent-usage/claude-limits.json"
if [[ -f $limits_cache ]]; then
  jq -r '"last good check: \(.fetchedAtMs / 1000 | strflocaltime("%H:%M:%S"))",
    (if .backoffUntilMs then "rate limited: paused \(.backoffSeconds)s, until \(.backoffUntilMs / 1000 | strflocaltime("%H:%M:%S"))" else "rate limited: no" end)' "$limits_cache" 2>&1
else
  echo "no checks yet"
fi

echo
echo "== GNOME Shell log for this extension (this boot)"
# Only GNOME Shell's own lines: other programs (sudo, apt) mention the
# install folder too.
{
  journalctl --user -b -o cat --no-pager _COMM=gnome-shell 2>/dev/null
  journalctl -b -o cat --no-pager _COMM=gnome-shell 2>/dev/null
} | grep -iE "agent-usage|$UUID" | awk '!seen[$0]++' | tail -40
