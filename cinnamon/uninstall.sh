#!/bin/bash
# Remove the Agent Usage applet for Cinnamon: off every panel, and its files.
# With --purge, also delete its settings and the usage data and caches the
# collectors wrote. uninstall.sh hands over to this.

set -euo pipefail

UUID="agent-usage@local"
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APPLET_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/cinnamon/applets/$UUID"
BIN_DIR="$HOME/.local/bin"

# shellcheck source=../scripts/common.sh
source "$ROOT/scripts/common.sh"

remove_session_hooks "$ROOT/agent-usage@local/hooks/agent-usage-session"

# Cinnamon unloads an applet as soon as it leaves enabled-applets.
if current=$(gsettings get org.cinnamon enabled-applets 2>/dev/null); then
  updated=$(python3 - "$current" "$UUID" <<'PY'
import ast, sys

raw, uuid = sys.argv[1:]
raw = raw.strip()
applets = ast.literal_eval(raw[3:].strip() if raw.startswith("@as") else raw)
print(str([entry for entry in applets if entry.count(":") < 4 or entry.split(":")[3].lstrip("!") != uuid]))
PY
)
  [[ $updated == "$current" ]] || gsettings set org.cinnamon enabled-applets "$updated"
fi

link="$BIN_DIR/agent-usage-update"
if [[ -L $link && $(readlink "$link") == "$APPLET_DIR"/* ]]; then
  rm -f "$link"
fi
rm -rf "$APPLET_DIR"
# The `agent-usage` command from a git install points into its checkout.
cli="$BIN_DIR/agent-usage"
if [[ -L $cli && $(readlink "$cli") == */bin/agent-usage ]]; then
  rm -f "$cli"
fi
echo "Removed the applet."

if [[ ${1:-} == --purge ]]; then
  rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/cinnamon/spices/$UUID"
  purge_usage_data
fi
