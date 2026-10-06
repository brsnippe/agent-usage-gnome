#!/bin/bash
# Run with: cinnamon/test/smoke-test.sh [snapshot folder]
#
# The applet in a real Cinnamon on a virtual screen: it has to install, load
# without errors, show the session limit in the panel, draw its panel, open
# the agent on a right click (Cinnamon's own menu, with that switched off),
# survive a reinstall, and take itself off the panel with its ⏻, keeping its
# settings for when it's added back. Meant for Linux Mint's Docker images, as a normal
# user with Cinnamon, Xvfb and a system bus running
# (cinnamon/test/run-in-mint.sh sets that up). Screenshots and logs go to the
# snapshot folder, cinnamon/snapshots by default.

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
APPLET="imports.ui.appletManager.getRunningInstancesForUuid('$UUID')[0]"
applet() { state eval "$APPLET$1"; }

# A button in the panel, by its label or the name screen readers read out;
# null when there's none.
button() {
  echo "(() => {
      const find = actor => {
        if (actor.accessible_name === '$1' || actor.get_label?.() === '$1') return actor;
        for (const child of actor.get_children()) {
          const found = find(child);
          if (found) return found;
        }
        return null;
      };
      return find($APPLET._controller.actor);
    })()"
}

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

# One of the applet's actors on screen, with a margin.
shot_actor() {
  local box
  box=$(state eval "(() => {
      const actor = imports.ui.appletManager.getRunningInstancesForUuid('$UUID')[0]$2;
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

# The open menu.
shot_menu() {
  shot_actor "$1" ".menu.actor"
}

# A session file, as the agents' hooks write it.
SESSIONS="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/agents/sessions"
session_file() {
  local now
  now=$(date +%s%3N)
  mkdir -p "$SESSIONS"
  printf '{"agent":"claude","session":"smoke","state":"%s","since":%s,"updated":%s,"pid":%s,"cwd":"%s"}\n' \
    "$1" "$now" "$now" "$$" "$HOME" >"$SESSIONS/.claude-smoke.tmp"
  mv "$SESSIONS/.claude-smoke.tmp" "$SESSIONS/claude-smoke.json"
}

# The color one of the applet's actors is drawn in, as rrggbb.
color_of() {
  state eval "(() => {
      const color = imports.ui.appletManager.getRunningInstancesForUuid('$UUID')[0]$1.get_theme_node().get_foreground_color();
      return [color.red, color.green, color.blue].map(value => value.toString(16).padStart(2, '0')).join('');
    })()"
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
# (The session hooks ask it for its version; that doesn't open anything.)
printf '#!/bin/sh\n[ "$1" = --version ] && exit 0\necho "$@" >"%s/opened"\n' "$OUT" >~/.local/bin/opencode
chmod +x ~/.local/bin/opencode
settings=$(ls "${XDG_CONFIG_HOME:-$HOME/.config}/cinnamon/spices/$UUID/"*.json 2>/dev/null | head -1)
check "Cinnamon set up the applet's settings" "$([[ -f $settings ]] && echo yes)" "yes"
# What the settings window does: write the file, then tell Cinnamon which
# key changed, naming the instance by the file's name. The value is JSON.
setting() {
  python3 - "$settings" "$1" "$2" <<'PY'
import json, sys
path, key, value = sys.argv[1:]
with open(path) as f:
    settings = json.load(f)
settings[key]["value"] = json.loads(value)
with open(path, "w") as f:
    json.dump(settings, f)
PY
  gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.updateSetting \
    "$UUID" "$(basename "$settings" .json)" "$1" "$2" >/dev/null
}
setting terminal-command '"env AGENT_USAGE_TERMINAL=1 {command}"'
setting terminal '"custom"'
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
check "the header has refresh, open, settings and switch-off buttons" \
  "$(applet "._controller.actor.get_children()[0].get_children().map(child => child.accessible_name).filter(Boolean).join(', ')")" \
  "Refresh now (r), Open OpenCode in env, Settings, Switch off (q)"
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

# ---- session colors: orange while a session waits for you, green once one
# is done, until the panel is opened. The robot pops and sounds each time.
setting session-sounds true
for _ in $(seq 20); do
  [[ $(applet "._settings.getValue('session-sounds')") == true ]] && break
  sleep 0.25
done
# Every step of the robot's size, and the sounds it plays (played for real
# too, into a machine without speakers).
state eval "(() => {
    const applet = $APPLET, icon = applet._applet_icon, controller = applet._controller;
    globalThis.agentUsageAlerts = {scales: [], sounds: []};
    icon.connect('notify::scale-x', () => agentUsageAlerts.scales.push(icon.scale_x));
    const play = controller._playSound.bind(controller);
    controller._playSound = alert => { agentUsageAlerts.sounds.push(alert); play(alert); };
  })()" >/dev/null
# The robot's size: how often it changed, how big it got, and where it is now.
pop_of() {
  state eval "(() => {
      const scales = agentUsageAlerts.scales;
      return [scales.length > 4 ? 'animated' : scales.length ? 'instant' : 'still', Math.max(1, ...scales).toFixed(1),
        $APPLET._applet_icon.scale_x].join(' ');
    })()"
}
# Animations on or off, as Cinnamon has them with effects switched on or off;
# without an argument, back to what Cinnamon had.
animations() {
  local wanted="${1:-}"
  state eval "(() => {
      const main = imports.ui.main, settings = imports.gi.St.Settings.get();
      const has = 'animations_enabled' in settings;
      globalThis.agentUsageAnimations ??= [main.animations_enabled, has && settings.animations_enabled];
      const [on, st] = '$wanted' === '' ? agentUsageAnimations : ['$wanted' === 'on', '$wanted' === 'on'];
      main.animations_enabled = on;
      if (has) settings.animations_enabled = st;
    })()" >/dev/null
}
animations off
session_file waiting
for _ in $(seq 20); do
  [[ $(applet "._applet_icon.has_style_class_name('agent-usage-waiting')") == true ]] && break
  sleep 0.25
done
check "a session waiting for you turns the robot orange" "$(color_of "._applet_icon")" "ffa066"
check "and leaves the number as it was" \
  "$(applet "._applet_label.get_text()") $(applet "._applet_label.has_style_class_name('agent-usage-waiting')")" "61% false"
sleep 1
check "with animations off, the robot doesn't pop" "$(pop_of)" "still 1.0 1"
check "but it plays the waiting sound" "$(state eval "agentUsageAlerts.sounds.join(' ')")" "waiting"
applet ".on_panel_height_changed()" >/dev/null
check "and stays orange when the panel changes height" "$(applet "._applet_icon.has_style_class_name('agent-usage-waiting')")" "true"
shot_actor topbar-waiting ".actor"
# What the pop looks like at its biggest.
applet "._applet_icon.set_pivot_point(0.5, 0.5)" >/dev/null
applet "._applet_icon.set_scale(1.5, 1.5)" >/dev/null
sleep 0.3
shot_actor topbar-pop ".actor"
applet "._applet_icon.set_scale(1, 1)" >/dev/null
state eval "agentUsageAlerts.scales = []" >/dev/null
# Alerts closer together than 3 seconds merge.
animations on
sleep 3
session_file ready
for _ in $(seq 20); do
  [[ $(applet "._applet_icon.has_style_class_name('agent-usage-ready')") == true ]] && break
  sleep 0.25
done
check "a finished turn turns it green" "$(color_of "._applet_icon")" "98bb6c"
sleep 1
check "and pops the robot: it grows to 1.5 and springs back" "$(pop_of)" "animated 1.5 1"
check "with the ready sound" "$(state eval "agentUsageAlerts.sounds.join(' ')")" "waiting ready"
animations
shot_actor topbar-ready ".actor"
applet ".on_applet_clicked()" >/dev/null
sleep 1
applet ".menu.close()" >/dev/null
check "opening the panel clears the green" "$(applet "._applet_icon.has_style_class_name('agent-usage-ready')")" "false"
check "quietly" "$(state eval "agentUsageAlerts.sounds.join(' ')")" "waiting ready"
rm -f "$SESSIONS/claude-smoke.json"
setting session-sounds false
sleep 1

# ---- the settings window's play buttons, pressed as that window presses
# them: they play also with Sounds switched off
for _ in $(seq 20); do
  [[ $(applet "._settings.getValue('session-sounds')") == false ]] && break
  sleep 0.25
done
for callback in playWaiting playReady; do
  gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.activateCallback \
    "$callback" "$UUID" "$(basename "$settings" .json)" >/dev/null
done
sleep 0.5
check "the play buttons play each sound, also with Sounds off" \
  "$(state eval "agentUsageAlerts.sounds.join(' ')")" "waiting ready waiting ready"

# ---- a right click opens the agent, outside panel edit mode
applet "._onButtonPressEvent(null, {get_button: () => 3})" >/dev/null
for _ in $(seq 20); do
  [[ -f $OUT/opened ]] && break
  sleep 0.25
done
check "a right click opens the agent, in the terminal from the settings" "$([[ -f $OUT/opened ]] && echo opened)" "opened"
check "and doesn't open the panel" "$(applet ".menu.isOpen")" "false"

# ---- with that switched off, a right click shows Cinnamon's own menu
rm -f "$OUT/opened"
setting right-click-opens-agent false
for _ in $(seq 20); do
  [[ $(applet "._settings.getValue('right-click-opens-agent')") == false ]] && break
  sleep 0.25
done
applet "._onButtonPressEvent(null, {get_button: () => 3})" >/dev/null
sleep 1
check "switched off, a right click shows Cinnamon's menu, not the agent" \
  "$(applet "._applet_context_menu.isOpen") $([[ -f $OUT/opened ]] && echo opened || echo 'not opened')" "true not opened"
shot_actor applet-menu "._applet_context_menu.actor"
applet "._applet_context_menu.close()" >/dev/null
setting right-click-opens-agent true

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

# ---- ⏻ asks, then takes it off the panel, until it's added back
applet ".on_applet_clicked()" >/dev/null
sleep 1
state eval "$(button 'Switch off (q)').emit('clicked', 1)" >/dev/null
sleep 0.5
check "⏻ asks first, in a card under the header" \
  "$(state eval "$APPLET._controller.actor.get_children()[1] === $(button 'Cancel').get_parent().get_parent() && $(button 'Switch off') !== null")" "true"
shot_menu panel-switch-off
state eval "$(button 'Cancel').emit('clicked', 1)" >/dev/null
sleep 0.5
check "Cancel takes the card away and leaves the panel open" "$(state eval "($(button 'Cancel') === null) + ' ' + $APPLET.menu.isOpen")" "true true"
applet "._controller.handleKey(imports.gi.Clutter.KEY_q)" >/dev/null
sleep 0.5
check "q asks too, with the focus on Switch off" "$(state eval "global.stage.get_key_focus() === $(button 'Switch off')")" "true"
state eval "$(button 'Switch off').emit('clicked', 1)" >/dev/null
for _ in $(seq 20); do
  [[ $(gsettings get org.cinnamon enabled-applets | grep -c ":$UUID:") == 0 ]] && break
  sleep 0.25
done
check "Switch off takes it off the panel, as Cinnamon's Remove does" \
  "$(gsettings get org.cinnamon enabled-applets | grep -o ":$UUID:" | wc -l) $(state eval "imports.ui.appletManager.getRunningInstancesForUuid('$UUID').length")" "0 0"
check "and keeps its settings" "$(jq -r '.terminal.value' "$settings")" "custom"
# Back, as Applets in System Settings adds it: a new instance on the panel.
next=$(gsettings get org.cinnamon next-applet-id | grep -oE '[0-9]+')
gsettings set org.cinnamon next-applet-id "$((next + 1))"
gsettings set org.cinnamon enabled-applets "$(gsettings get org.cinnamon enabled-applets | sed -E "s/]\$/, 'panel1:right:0:$UUID:$next']/")"
for _ in $(seq 20); do
  [[ $(applet "._controller.launchSettings().terminal" 2>/dev/null) == custom ]] && break
  sleep 0.5
done
check "added back, it loads with the same settings" "$(state status) $(applet "._controller.launchSettings().terminal")" "Loaded custom"

# ---- nothing went wrong along the way
state log >"$OUT/applet-log.txt" 2>&1
check "Cinnamon logged no errors from the applet" "$(grep -c '^error:' "$OUT/applet-log.txt")" "0"
check "nor any deprecation warnings" "$(grep -ci 'deprecated' "$OUT/applet-log.txt")" "0"
check "and played the sounds without one" "$(grep -c 'could not play a sound' "$OUT/applet-log.txt")" "0"
