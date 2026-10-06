#!/bin/bash
# Install (or reinstall) the Agent Usage applet for Cinnamon, Linux Mint's
# desktop, for the current user. install.sh hands over to this in a Cinnamon
# session.
#
# Unlike GNOME, Cinnamon picks up the new code right away: a first install
# adds the applet to the panel, which loads it, and a reinstall reloads it.

set -euo pipefail

UUID="agent-usage@local"
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APPLET_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/cinnamon/applets/$UUID"
BIN_DIR="$HOME/.local/bin"

# shellcheck source=../scripts/common.sh
source "$ROOT/scripts/common.sh"

if [[ $EUID -eq 0 ]]; then
  echo "Run this as your normal user, not with sudo. It asks for sudo itself when it needs to install packages." >&2
  exit 1
fi
if [[ ${XDG_CURRENT_DESKTOP:-} != *Cinnamon* ]] || ! command -v cinnamon >/dev/null; then
  echo "This is a Cinnamon applet; run it inside a Cinnamon session (Linux Mint's default desktop)." >&2
  exit 1
fi
cinnamon_version=$(cinnamon --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
if ! printf '6.0\n%s\n' "$cinnamon_version" | sort -V -C; then
  echo "Cinnamon $cinnamon_version is too old; the applet needs Cinnamon 6.0 or newer (Linux Mint 21.3+)." >&2
  exit 1
fi

# The applet's entries in org.cinnamon's enabled-applets, which lists every
# applet on every panel as panel:zone:order:uuid:instance.
on_panel() {
  gsettings get org.cinnamon enabled-applets | grep -q ":!\{0,1\}$UUID:"
}

# First in the right-hand zone, next to the status icons, on the panel that
# has them (Mint's default panel has them at the bottom right).
add_to_panel() {
  local current next updated
  current=$(gsettings get org.cinnamon enabled-applets)
  next=$(gsettings get org.cinnamon next-applet-id | grep -oE '[0-9]+')
  updated=$(python3 - "$current" "$UUID" "$next" <<'PY'
import ast, sys

raw, uuid, instance = sys.argv[1:]
raw = raw.strip()
applets = ast.literal_eval(raw[3:].strip() if raw.startswith("@as") else raw)
entries = [entry.split(":") for entry in applets if entry.count(":") >= 4]
status = [e[0] for e in entries if e[3].lstrip("!") in ("xapp-status@cinnamon.org", "systray@cinnamon.org")]
panels = sorted({e[0] for e in entries})
panel = status[0] if status else ("panel1" if "panel1" in panels or not panels else panels[0])
orders = [int(e[2]) for e in entries if e[0] == panel and e[1] == "right" and e[2].lstrip("-").isdigit()]
order = min(orders) - 1 if orders else 0
applets.append(f"{panel}:right:{order}:{uuid}:{instance}")
print(str(applets))
PY
)
  gsettings set org.cinnamon next-applet-id "$((next + 1))"
  gsettings set org.cinnamon enabled-applets "$updated"
}

reload_applet() {
  gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon \
    --method org.Cinnamon.ReloadXlet "$UUID" APPLET >/dev/null 2>&1
}

# Cinnamon loads the applet a moment after being asked to. Prints nothing
# when Cinnamon can't be asked at all.
wait_until_loaded() {
  local state=""
  for _ in $(seq 20); do
    state=$(python3 "$ROOT/cinnamon/cinnamon-state.py" status 2>/dev/null) || return 0
    [[ $state == Loaded ]] && break
    sleep 0.5
  done
  echo "$state"
}

step "Checking packages"
ensure_packages python3 jq fonts-jetbrains-mono libglib2.0-bin

read_version "$ROOT"

step "Installing the applet ($VERSION_NAME)"
reinstall=false
[[ -d $APPLET_DIR ]] && reinstall=true
mkdir -p "$BIN_DIR"
"$ROOT/cinnamon/build-applet.sh" "$APPLET_DIR" "$VERSION_NAME"
ln -sf "$APPLET_DIR/bin/agent-usage-update" "$BIN_DIR/agent-usage-update"
# A git install can update itself: the panel checks for new releases through
# this checkout, and `agent-usage` drives it.
if $FROM_GIT; then
  printf '%s\n' "$ROOT" >"$APPLET_DIR/source"
  chmod +x "$ROOT/bin/agent-usage"
  ln -sf "$ROOT/bin/agent-usage" "$BIN_DIR/agent-usage"
fi
echo "  $APPLET_DIR"

# Kept as it was, when someone switched it off.
colors=true
for settings in "${XDG_CONFIG_HOME:-$HOME/.config}/cinnamon/spices/$UUID"/*.json; do
  if [[ -f $settings && $(jq -r '."session-colors".value' "$settings" 2>/dev/null) == false ]]; then
    colors=false
  fi
done
install_session_hooks "$APPLET_DIR/hooks/agent-usage-session" "$colors"

# Before the applet loads, so it opens on fresh numbers.
step "Collecting usage"
"$APPLET_DIR/bin/agent-usage-update" --force || note "A collector failed; the messages above say which."
summarize_usage || note "No agent has usage yet; the panel says so. Sign in with: claude auth login / codex login"

step "Loading it"
loaded=true
if on_panel; then
  reload_applet || loaded=false
  $loaded && echo "  Reloaded in the panel."
elif $reinstall; then
  # Someone took it off the panel; an update doesn't put it back.
  loaded=false
  note "It isn't on a panel. To add it: right-click the panel, Applets, then Agent Usage."
else
  add_to_panel
  echo "  Added to the panel, next to the status icons."
fi
if $loaded; then
  state=$(wait_until_loaded)
  case "$state" in
  Loaded) echo "  Cinnamon loaded it." ;;
  "") note "Couldn't ask Cinnamon whether it loaded; if the robot isn't in the panel, log out and back in." ;;
  *) note "Cinnamon didn't load it ($state). Run agent-usage diagnose (or ./diagnose.sh) and send the output." ;;
  esac
fi

step "Next"
echo "  The robot in the panel: left-click opens the panel, right-click opens your agent, middle-click refreshes."
echo "  Settings (refresh intervals, session colors, agent, terminal, updates): the ⚙ button in the panel, or System Settings → Applets."
if $FROM_GIT; then
  echo "  Updates: agent-usage update (the panel also says when there's a new version)"
  echo "  If something looks wrong: agent-usage diagnose"
else
  echo "  If something looks wrong: ./diagnose.sh"
fi
