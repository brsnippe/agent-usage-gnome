#!/bin/bash
# Remove the Agent Usage extension (including earlier builds under their old
# ids). With --purge, also delete the usage data and caches the collectors
# wrote, and the extension's settings.

set -euo pipefail

UUIDS=("agent-usage@local" "agent-usage@brsnippe.github.io")
EXTENSIONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions"
BIN_DIR="$HOME/.local/bin"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

for uuid in "${UUIDS[@]}"; do
  gnome-extensions disable "$uuid" 2>/dev/null || true
  current=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "[]")
  updated=$(python3 - "$current" "$uuid" <<'PY'
import ast, sys
raw, uuid = sys.argv[1], sys.argv[2]
raw = raw.strip()
items = ast.literal_eval(raw[3:].strip() if raw.startswith("@as") else raw)
print(str([item for item in items if item != uuid]))
PY
)
  gsettings set org.gnome.shell enabled-extensions "$updated" 2>/dev/null || true

  link="$BIN_DIR/agent-usage-update"
  if [[ -L $link && $(readlink "$link") == "$EXTENSIONS_DIR/$uuid"/* ]]; then
    rm -f "$link"
  fi
  rm -rf "${EXTENSIONS_DIR:?}/$uuid"
done
# The `agent-usage` command from a git install points into its checkout.
cli="$BIN_DIR/agent-usage"
if [[ -L $cli && $(readlink "$cli") == */bin/agent-usage ]]; then
  rm -f "$cli"
fi
echo "Removed the extension."

if [[ ${1:-} == --purge ]]; then
  dconf reset -f /org/gnome/shell/extensions/agent-usage/ 2>/dev/null || true
  # These folders keep Omarchy's names, and on an Omarchy machine they belong
  # to Omarchy's own bar widget.
  if [[ -d /usr/share/omarchy ]]; then
    echo "Omarchy is installed here and uses the same folders; leaving the usage data alone."
  else
    rm -rf "$STATE_HOME/omarchy/agents/usage" "$CACHE_HOME/omarchy/agent-usage"
    rmdir "$STATE_HOME/omarchy/agents" "$STATE_HOME/omarchy" "$CACHE_HOME/omarchy" 2>/dev/null || true
    echo "Deleted the collected usage data, caches and settings."
  fi
fi
