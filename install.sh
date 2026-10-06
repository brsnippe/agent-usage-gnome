#!/bin/bash
# Install (or reinstall) the Agent Usage GNOME Shell extension for the current
# user. Also removes the older tray-icon version if it's installed. In a
# Cinnamon session (Linux Mint), installs the Cinnamon applet instead.

set -euo pipefail

UUID="agent-usage@local"
# Earlier builds of this extension went by these ids.
OLD_UUIDS=("agent-usage@brsnippe.github.io")
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
EXTENSIONS_DIR="$DATA_HOME/gnome-shell/extensions"
EXT_DIR="$EXTENSIONS_DIR/$UUID"
BIN_DIR="$HOME/.local/bin"
OLD_APP_DIR="$DATA_HOME/agent-usage-tray"
OLD_AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/agent-usage-tray.desktop"
OLD_LAUNCHER="$DATA_HOME/applications/agent-usage-tray.desktop"

if [[ ${XDG_CURRENT_DESKTOP:-} == *Cinnamon* ]]; then
  exec "$SRC/cinnamon/install.sh" "$@"
fi

# shellcheck source=scripts/common.sh
source "$SRC/scripts/common.sh"

# Add or remove a uuid in one of org.gnome.shell's string-list settings.
edit_list() {
  local key="$1" action="$2" uuid="${3:-$UUID}" current updated
  current=$(gsettings get org.gnome.shell "$key")
  updated=$(python3 - "$current" "$uuid" "$action" <<'PY'
import ast, sys
raw, uuid, action = sys.argv[1:]
raw = raw.strip()
items = ast.literal_eval(raw[3:].strip() if raw.startswith("@as") else raw)
items = [item for item in items if item != uuid]
if action == "add":
    items.append(uuid)
print(str(items))
PY
)
  gsettings set org.gnome.shell "$key" "$updated"
}

if [[ $EUID -eq 0 ]]; then
  echo "Run this as your normal user, not with sudo. It asks for sudo itself when it needs to install packages." >&2
  exit 1
fi
if [[ ${XDG_CURRENT_DESKTOP:-} != *GNOME* ]] || ! command -v gnome-shell >/dev/null; then
  echo "This is a GNOME Shell extension (and a Cinnamon applet); run it inside a GNOME or Cinnamon session." >&2
  exit 1
fi
shell_version=$(gnome-shell --version | grep -oE '[0-9]+' | head -1)
if ((shell_version < 46)); then
  echo "GNOME $shell_version is too old; this extension needs GNOME 46 or newer (Ubuntu 24.04+)." >&2
  exit 1
fi

step "Checking packages"
ensure_packages python3 jq fonts-jetbrains-mono libglib2.0-bin

if [[ -d $OLD_APP_DIR || -e $OLD_AUTOSTART || -e $OLD_LAUNCHER ]]; then
  step "Removing the old tray-icon version"
  pkill -f '^([^ ]*/)?python3(\.[0-9]+)? ([^ ]*/)?agent-usage-tray( |$)' 2>/dev/null || true
  rm -f "$OLD_AUTOSTART" "$OLD_LAUNCHER"
  for link in "$BIN_DIR/agent-usage-tray" "$BIN_DIR/agent-usage-update"; do
    if [[ -L $link && $(readlink "$link") == "$OLD_APP_DIR"/* ]]; then
      rm -f "$link"
    fi
  done
  rm -rf "$OLD_APP_DIR"
  echo "  Removed. Your collected usage data is kept."
fi

for old in "${OLD_UUIDS[@]}"; do
  [[ -d $EXTENSIONS_DIR/$old ]] || continue
  step "Removing the earlier build ($old)"
  gnome-extensions disable "$old" 2>/dev/null || true
  edit_list enabled-extensions remove "$old"
  edit_list disabled-extensions remove "$old"
  if [[ -L $BIN_DIR/agent-usage-update && $(readlink "$BIN_DIR/agent-usage-update") == "$EXTENSIONS_DIR/$old"/* ]]; then
    rm -f "$BIN_DIR/agent-usage-update"
  fi
  rm -rf "${EXTENSIONS_DIR:?}/$old"
  echo "  Removed. Your settings and usage data are kept."
done

# The version GNOME's Extensions app and the update check see.
read_version "$SRC"

step "Installing the extension ($VERSION_NAME)"
reinstall=false
[[ -d $EXT_DIR ]] && reinstall=true
rm -rf "$EXT_DIR"
mkdir -p "$(dirname "$EXT_DIR")" "$BIN_DIR"
cp -r "$SRC/$UUID" "$EXT_DIR"
chmod +x "$EXT_DIR"/bin/* "$EXT_DIR/hooks/agent-usage-session"
glib-compile-schemas --strict "$EXT_DIR/schemas"
jq --arg version "$VERSION_NAME" '.["version-name"] = $version' "$SRC/$UUID/metadata.json" >"$EXT_DIR/metadata.json"
ln -sf "$EXT_DIR/bin/agent-usage-update" "$BIN_DIR/agent-usage-update"
# A git install can update itself: the panel checks for new releases through
# this checkout, and `agent-usage` drives it.
if $FROM_GIT; then
  printf '%s\n' "$SRC" >"$EXT_DIR/source"
  chmod +x "$SRC/bin/agent-usage"
  ln -sf "$SRC/bin/agent-usage" "$BIN_DIR/agent-usage"
fi
echo "  $EXT_DIR"

if [[ $(gsettings get org.gnome.shell disable-user-extensions) == "true" ]]; then
  gsettings set org.gnome.shell disable-user-extensions false
  note "User extensions were switched off in GNOME; switched them back on."
fi
edit_list disabled-extensions remove
# `gnome-extensions enable` only knows extensions the running shell has
# loaded; a first install goes straight into the setting for the next login.
if ! gnome-extensions enable "$UUID" 2>/dev/null; then
  edit_list enabled-extensions add
fi
echo "  Enabled."

# Kept as it was, when someone switched it off.
colors=$(gsettings --schemadir "$EXT_DIR/schemas" get org.gnome.shell.extensions.agent-usage session-colors 2>/dev/null || true)
install_session_hooks "$EXT_DIR/hooks/agent-usage-session" "$colors"

step "Collecting usage"
"$EXT_DIR/bin/agent-usage-update" --force || note "A collector failed; the messages above say which."
summarize_usage || note "No agent has usage yet, so the icon stays hidden until one does. Sign in with: claude auth login / codex login"

step "Next"
if $reinstall; then
  echo "  GNOME keeps running the previous version until it restarts."
else
  echo "  GNOME only picks up new extensions when it starts."
fi
if [[ ${XDG_SESSION_TYPE:-} == x11 ]]; then
  echo "  To load it now: press Alt+F2, type r, press Enter. Your windows stay open."
else
  echo "  To load it: log out and back in."
  echo "  To look at it right now without logging out: $SRC/preview.sh"
fi
echo "  Settings (refresh intervals, session colors, agent, terminal, updates): the ⚙ button in the panel, or: gnome-extensions prefs $UUID"
if $FROM_GIT; then
  echo "  Updates: agent-usage update (the panel also says when there's a new version)"
  echo "  If something looks wrong: agent-usage diagnose"
else
  echo "  If something looks wrong: ./diagnose.sh"
fi
