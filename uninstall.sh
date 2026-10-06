#!/bin/bash
# Remove the Agent Usage extension (including earlier builds under their old
# ids). With --purge, also delete the usage data and caches the collectors
# wrote, and the extension's settings. In a Cinnamon session, or where only
# the Cinnamon applet is installed, removes the applet instead.

set -euo pipefail

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
UUIDS=("agent-usage@local" "agent-usage@brsnippe.github.io")
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
EXTENSIONS_DIR="$DATA_HOME/gnome-shell/extensions"
BIN_DIR="$HOME/.local/bin"

if [[ ${XDG_CURRENT_DESKTOP:-} == *Cinnamon* ]] ||
  [[ -d $DATA_HOME/cinnamon/applets/agent-usage@local && ! -d $EXTENSIONS_DIR/agent-usage@local ]]; then
  exec "$SRC/cinnamon/uninstall.sh" "$@"
fi

# shellcheck source=scripts/common.sh
source "$SRC/scripts/common.sh"

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
  purge_usage_data
fi
