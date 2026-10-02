#!/bin/bash
# Open a separate GNOME Shell in a window, running the installed version of
# the extension, so changes can be checked without logging out.

set -euo pipefail

UUID="agent-usage@local"
EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$UUID"
[[ -d $EXT_DIR ]] || { echo "Run ./install.sh first." >&2; exit 1; }

export MUTTER_DEBUG_DUMMY_MODE_SPECS="${MUTTER_DEBUG_DUMMY_MODE_SPECS:-1400x900}"
echo "Opening GNOME Shell in a window. The icon is in its top bar, on the right."
echo "Close the window (or press Ctrl+C here) when you're done."

shell_version=$(gnome-shell --version | grep -oE '[0-9]+' | head -1)
if ((shell_version >= 49)); then
  exec dbus-run-session -- gnome-shell --devkit --wayland
else
  exec dbus-run-session -- gnome-shell --nested --wayland
fi
