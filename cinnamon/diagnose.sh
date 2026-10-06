#!/bin/bash
# Print what's needed to debug the Cinnamon applet. Paste the output when
# something looks wrong. diagnose.sh hands over to this.

UUID="agent-usage@local"
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APPLET_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/cinnamon/applets/$UUID"
SETTINGS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cinnamon/spices/$UUID"

# shellcheck source=../scripts/common.sh
source "$ROOT/scripts/common.sh"

echo "== Cinnamon"
cinnamon --version 2>&1
echo "system: $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-?}")"
echo "session: ${XDG_SESSION_TYPE:-?} ${XDG_CURRENT_DESKTOP:-?}"

echo
echo "== Applet"
echo "installed: $([[ -f $APPLET_DIR/metadata.json ]] && echo "yes, version $(jq -r '.version // "unknown"' "$APPLET_DIR/metadata.json" 2>/dev/null)" || echo "no ($APPLET_DIR is missing; run ./install.sh)")"
print_source "$APPLET_DIR/source"
echo "on the panel: $(gsettings get org.cinnamon enabled-applets 2>/dev/null | grep -oE "[^' ]*:!?$UUID:[0-9]+" | tr '\n' ' ' || true)"
echo "loaded: $(python3 "$ROOT/cinnamon/cinnamon-state.py" status 2>&1)"
for settings in "$SETTINGS_DIR"/*.json; do
  [[ -f $settings ]] || continue
  echo "settings ($(basename "$settings")):"
  jq -r 'to_entries[] | select(.value | type == "object" and has("value")) | "  \(.key): \(.value.value | tojson)"' "$settings" 2>&1
done

print_usage_records
print_session_colors "$APPLET_DIR/hooks/agent-usage-session"

echo
echo "== Cinnamon's log for this applet"
python3 "$ROOT/cinnamon/cinnamon-state.py" log 2>&1 | tail -40
# The collectors' and the panel's own messages go to the session's output.
if [[ -f $HOME/.xsession-errors ]]; then
  echo "-- ~/.xsession-errors"
  grep -iE "agent-usage|$UUID" "$HOME/.xsession-errors" | awk '!seen[$0]++' | tail -40
fi
