#!/bin/bash
# Print what's needed to debug the extension. Paste the output when
# something looks wrong. In a Cinnamon session, or where only the Cinnamon
# applet is installed, it's about the applet instead.

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
UUID="agent-usage@local"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
EXT_DIR="$DATA_HOME/gnome-shell/extensions/$UUID"

if [[ ${XDG_CURRENT_DESKTOP:-} == *Cinnamon* ]] || [[ -d $DATA_HOME/cinnamon/applets/$UUID && ! -d $EXT_DIR ]]; then
  exec "$SRC/cinnamon/diagnose.sh" "$@"
fi

# shellcheck source=scripts/common.sh
source "$SRC/scripts/common.sh"

echo "== GNOME"
gnome-shell --version
echo "session: ${XDG_SESSION_TYPE:-?} ${XDG_CURRENT_DESKTOP:-?}"

echo
echo "== Extension"
echo "installed: $([[ -f $EXT_DIR/metadata.json ]] && echo "yes, version $(jq -r '.["version-name"] // "build \(.version)"' "$EXT_DIR/metadata.json" 2>/dev/null)" || echo "no ($EXT_DIR is missing; run ./install.sh)")"
print_source "$EXT_DIR/source"
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
# The panel's ⏻ puts it here; the Extensions app takes it out again.
echo "disabled-extensions: $(gsettings get org.gnome.shell disabled-extensions)"
for key in limits-interval scan-interval session-threshold session-colors session-pop session-sounds agent agent-command terminal terminal-command; do
  echo "$key: $(gsettings --schemadir "$EXT_DIR/schemas" get org.gnome.shell.extensions.agent-usage "$key" 2>&1)"
done

print_usage_records
print_session_colors "$EXT_DIR/hooks/agent-usage-session"

echo
echo "== GNOME Shell log for this extension (this boot)"
# Only GNOME Shell's own lines: other programs (sudo, apt) mention the
# install folder too.
{
  journalctl --user -b -o cat --no-pager _COMM=gnome-shell 2>/dev/null
  journalctl -b -o cat --no-pager _COMM=gnome-shell 2>/dev/null
} | grep -iE "agent-usage|$UUID" | awk '!seen[$0]++' | tail -40
