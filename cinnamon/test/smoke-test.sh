#!/bin/bash
# Run with: cinnamon/test/smoke-test.sh [snapshot folder]
#
# The applet in a real Cinnamon on a virtual screen: it has to install, load
# without errors, show the session limit in the panel, draw its panel, and
# survive a reinstall. Meant for Linux Mint's Docker images, as a normal user
# with Cinnamon, Xvfb and a system bus running (cinnamon/test/run-in-mint.sh
# sets that up). Screenshots and logs go to the snapshot folder,
# cinnamon/snapshots by default.

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OUT="${1:-$ROOT/cinnamon/snapshots}"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

# A session bus of its own, as a login has. The runtime folder has to be set
# before the bus starts: dconf's service, which the bus starts, and its
# readers (Cinnamon, gsettings) otherwise disagree on where to look for
# changes, and Cinnamon never sees the installer's.
if [[ -z ${AGENT_USAGE_SMOKE_SESSION:-} ]]; then
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
  mkdir -p "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"
  # The bus and the services it starts are chatty; their messages go to a log.
  exec env AGENT_USAGE_SMOKE_SESSION=1 dbus-run-session -- "$0" "$OUT" 2>"$OUT/session.log"
fi

UUID="agent-usage@local"
APPLET_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/cinnamon/applets/$UUID"
failures=0

check() {
  local name="$1" actual="$2" expected="$3"
  if [[ $actual == "$expected" ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    echo "     got      $actual"
    echo "     expected $expected"
    failures=$((failures + 1))
  fi
}

state() { python3 "$ROOT/cinnamon/cinnamon-state.py" "$@"; }
# JavaScript on the applet, inside Cinnamon.
applet() { state eval "imports.ui.appletManager.getRunningInstancesForUuid('$UUID')[0]$1"; }

# Cinnamon draws the screenshot itself, so it shows exactly what's on screen.
shot() {
  local name="$1"
  shift
  if (($# == 4)); then
    gdbus call --session --dest org.gnome.Shell.Screenshot --object-path /org/gnome/Shell/Screenshot \
      --method org.gnome.Shell.Screenshot.ScreenshotArea "$@" false "$OUT/$name.png" >/dev/null
  else
    gdbus call --session --dest org.gnome.Shell.Screenshot --object-path /org/gnome/Shell/Screenshot \
      --method org.gnome.Shell.Screenshot.Screenshot false false "$OUT/$name.png" >/dev/null
  fi
}

# The open menu, with a margin.
shot_menu() {
  local box
  box=$(state eval "(() => {
      const actor = imports.ui.appletManager.getRunningInstancesForUuid('$UUID')[0].menu.actor;
      const [x, y] = actor.get_transformed_position();
      const [w, h] = actor.get_transformed_size();
      const left = Math.max(0, Math.round(x - 8)), top = Math.max(0, Math.round(y - 8));
      const right = Math.min(global.stage.width, Math.round(x + w + 8));
      const bottom = Math.min(global.stage.height, Math.round(y + h + 8));
      return [left, top, right - left, bottom - top].join(' ');
    })()")
  # shellcheck disable=SC2086
  shot "$1" $box
}

finish() {
  state log >"$OUT/applet-log.txt" 2>&1
  kill "$cinnamon_pid" "$xvfb_pid" 2>/dev/null
  echo
  if ((failures)); then
    echo "--- install.log"
    cat "$OUT/install.log"
    echo "--- the applet's lines in Cinnamon's log"
    cat "$OUT/applet-log.txt"
    echo
    echo "$failures failed"
    exit 1
  fi
  echo "all passed"
}

export DISPLAY=:99 XDG_CURRENT_DESKTOP=X-Cinnamon XDG_SESSION_TYPE=x11 XDG_SESSION_DESKTOP=cinnamon

Xvfb :99 -screen 0 1280x900x24 -nolisten tcp >"$OUT/xvfb.log" 2>&1 &
xvfb_pid=$!
for _ in $(seq 50); do
  [[ -e /tmp/.X11-unix/X99 ]] && break
  sleep 0.1
done
cinnamon --replace >"$OUT/cinnamon.log" 2>&1 &
cinnamon_pid=$!
for _ in $(seq 120); do
  state status >/dev/null 2>&1 && break
  sleep 0.5
done
check "Cinnamon starts on the virtual screen" "$(state status >/dev/null 2>&1 && echo up)" "up"
echo "     $(cinnamon --version), loading applets the $(state eval \
  "typeof imports.ui.extension.getCurrentExtension === 'function' ? '6.8' : '6.0 to 6.6'") way"
trap finish EXIT

# ---- install: on the panel and loaded, without a logout
"$ROOT/install.sh" >"$OUT/install.log" 2>&1
check "install.sh succeeds" "$?" "0"
check "the installer adds the applet to the panel" "$(gsettings get org.cinnamon enabled-applets | grep -o ":$UUID:" | wc -l)" "1"
check "Cinnamon loads it" "$(state status)" "Loaded"
check "and says so to the installer" "$(grep -c 'Cinnamon loaded it.' "$OUT/install.log")" "1"
shot desktop-empty

# ---- a stand-in OpenCode, opened in a "terminal" set in the settings
mkdir -p ~/.local/bin
printf '#!/bin/sh\necho "$@" >"%s/opened"\n' "$OUT" >~/.local/bin/opencode
chmod +x ~/.local/bin/opencode
settings=$(ls "${XDG_CONFIG_HOME:-$HOME/.config}/cinnamon/spices/$UUID/"*.json 2>/dev/null | head -1)
check "Cinnamon set up the applet's settings" "$([[ -f $settings ]] && echo yes)" "yes"
# What the settings window does: write the file, then tell Cinnamon which
# keys changed, naming the instance by the file's name.
python3 - "$settings" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    settings = json.load(f)
settings["terminal"]["value"] = "custom"
settings["terminal-command"]["value"] = "env AGENT_USAGE_TERMINAL=1 {command}"
with open(path, "w") as f:
    json.dump(settings, f)
PY
for key in terminal-command terminal; do
  gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.updateSetting \
    "$UUID" "$(basename "$settings" .json)" "$key" "$(jq -c --arg key "$key" '.[$key].value' "$settings")" >/dev/null
done
for _ in $(seq 20); do
  [[ $(applet "._controller.launchSettings().terminal") == custom ]] && break
  sleep 0.5
done
check "a change in the settings window reaches the panel" "$(applet "._controller.launchSettings().terminal")" "custom"

# ---- the panel, with numbers in every section
for agent in claude codex; do
  cp "$ROOT/test/fake-collector" "$APPLET_DIR/bin/agent-usage-$agent"
done
applet ".on_applet_middle_clicked()" >/dev/null
for _ in $(seq 20); do
  [[ $(applet "._applet_label.get_text()") == "61%" ]] && break
  sleep 0.5
done
check "a middle click refreshes, and the panel shows the session limit" "$(applet "._applet_label.get_text()")" "61%"
check "with one tab per agent" "$(applet "._controller._providers.map(record => record.id).join(' ')")" "claude codex"

applet ".on_applet_clicked()" >/dev/null
sleep 2
check "a left click opens the panel" "$(applet ".menu.isOpen")" "true"
check "the panel has every section" \
  "$(applet "._controller.actor.get_children().length")" "11"
check "the header has refresh, open and settings buttons" \
  "$(applet "._controller.actor.get_children()[0].get_children().map(child => child.accessible_name).filter(Boolean).join(', ')")" \
  "Refresh now (r), Open OpenCode in env, Settings"
check "the panel is in JetBrains Mono" "$(applet "._controller.actor.get_theme_node().get_font().get_family().split(',')[0]")" "JetBrains Mono"
shot desktop-open
shot_menu panel-claude

applet "._controller._select('codex')" >/dev/null
sleep 1
check "the Codex tab has the problem card with its sign-in button" \
  "$(state eval "(() => {
      const panel = imports.ui.appletManager.getRunningInstancesForUuid('$UUID')[0]._controller.actor;
      const labels = [];
      const walk = actor => {
        if (actor.get_label && typeof actor.get_label() === 'string') labels.push(actor.get_label());
        actor.get_children().forEach(walk);
      };
      walk(panel);
      return labels.includes('Sign in') ? 'yes' : labels.join('|');
    })()")" "yes"
shot_menu panel-codex
applet ".menu.close()" >/dev/null
sleep 1

# ---- a right click opens the agent, outside panel edit mode
applet "._onButtonPressEvent(null, {get_button: () => 3})" >/dev/null
for _ in $(seq 20); do
  [[ -f $OUT/opened ]] && break
  sleep 0.25
done
check "a right click opens the agent, in the terminal from the settings" "$([[ -f $OUT/opened ]] && echo opened)" "opened"
check "and doesn't open the panel" "$(applet ".menu.isOpen")" "false"

# ---- the settings window, as Configure… or the ⚙ button opens it
applet ".configureApplet()" >/dev/null
sleep 5
shot settings
pkill -f xlet-settings 2>/dev/null

# ---- a reinstall reloads it in place
"$ROOT/install.sh" >"$OUT/reinstall.log" 2>&1
check "a reinstall succeeds" "$?" "0"
check "and reloads the applet, which loads again" "$(grep -c 'Reloaded in the panel.' "$OUT/reinstall.log") $(state status)" "1 Loaded"
check "still on the panel once" "$(gsettings get org.cinnamon enabled-applets | grep -o ":$UUID:" | wc -l)" "1"

# ---- nothing went wrong along the way
state log >"$OUT/applet-log.txt" 2>&1
check "Cinnamon logged no errors from the applet" "$(grep -c '^error:' "$OUT/applet-log.txt")" "0"
check "nor any deprecation warnings" "$(grep -ci 'deprecated' "$OUT/applet-log.txt")" "0"
