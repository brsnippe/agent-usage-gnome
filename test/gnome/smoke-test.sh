#!/bin/bash
# Run with: test/gnome/smoke-test.sh [snapshot folder]
#
# The GNOME extension in a real GNOME Shell, headless: it has to install, load
# without errors, stay out of the top bar until there's usage, show the
# session limit, draw its panel, take real clicks (right opens the agent, or
# the panel with that switched off; middle refreshes), and switch itself off
# with the panel's ⏻ until it's switched back on. Meant for
# Ubuntu's Docker images, as a normal user with a system bus and logind
# (test/gnome/prepare-ubuntu.sh sets that up). Screenshots and logs go to the
# snapshot folder, test/gnome/snapshots by default.
#
# GNOME Shell runs in its unsafe mode, which lets this script look inside it
# (org.gnome.Shell.Eval) and take screenshots.

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OUT="${1:-$ROOT/test/gnome/snapshots}"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

# A session bus of its own, as a login has; see cinnamon/test/smoke-test.sh
# for why the runtime folder comes first.
if [[ -z ${AGENT_USAGE_SMOKE_SESSION:-} ]]; then
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
  mkdir -p "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"
  exec env AGENT_USAGE_SMOKE_SESSION=1 dbus-run-session -- "$0" "$OUT" 2>"$OUT/session.log"
fi

UUID="agent-usage@local"
EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$UUID"
INDICATOR="Main.panel.statusArea['$UUID']"
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

# JavaScript inside GNOME Shell; prints the result as text. (Through Python,
# since gdbus would read code such as 'up' as a GVariant.)
shell() {
  python3 - "$1" <<'PY'
import json, sys
from gi.repository import Gio, GLib
try:
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    ok, value = bus.call_sync("org.gnome.Shell", "/org/gnome/Shell", "org.gnome.Shell", "Eval",
                              GLib.Variant("(s)", (sys.argv[1],)), None, Gio.DBusCallFlags.NONE, 5000, None).unpack()
except GLib.Error as error:
    print(error.message)
    sys.exit()
result = json.loads(value) if ok and value else value
print(result if isinstance(result, str) else json.dumps(result))
PY
}

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

# An actor on screen, with a margin.
shot_actor() {
  # shellcheck disable=SC2046
  shot "$1" $(shell "(() => {
      const actor = $2;
      const [x, y] = actor.get_transformed_position();
      const [w, h] = actor.get_transformed_size();
      const left = Math.max(0, Math.round(x - 8)), top = Math.max(0, Math.round(y - 8));
      const right = Math.min(global.stage.width, Math.round(x + w + 8));
      const bottom = Math.min(global.stage.height, Math.round(y + h + 8));
      return [left, top, right - left, bottom - top].join(' ');
    })()")
}

shot_menu() {
  shot_actor "$1" "$INDICATOR.menu.actor"
}

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
      return find($INDICATOR._controller.actor);
    })()"
}

# A click on the robot through a virtual pointer, so it goes where a mouse's
# goes, GNOME 50's click gesture included. 1 is left, 2 middle, 3 right.
click() {
  shell "(globalThis.agentUsagePointer ??= imports.gi.Clutter.get_default_backend().get_default_seat()
    .create_virtual_device(imports.gi.Clutter.InputDeviceType.POINTER_DEVICE), 'ready')" >/dev/null
  # A new pointer misses its first moves, so move until the robot feels it.
  for _ in $(seq 20); do
    shell "(() => {
        const [x, y] = $INDICATOR.get_transformed_position();
        const [w, h] = $INDICATOR.get_transformed_size();
        agentUsagePointer.notify_absolute_motion(imports.gi.GLib.get_monotonic_time(), x + w / 2, y + h / 2);
      })()" >/dev/null
    sleep 0.25
    [[ $(shell "$INDICATOR.hover") == true ]] && break
  done
  for state in PRESSED RELEASED; do
    shell "agentUsagePointer.notify_button(imports.gi.GLib.get_monotonic_time(), $1, imports.gi.Clutter.ButtonState.$state)" >/dev/null
    sleep 0.3
  done
  sleep 1
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

# What the settings window's play buttons do: ask GNOME Shell over D-Bus.
play_sound() {
  gdbus call --session --dest org.gnome.Shell --object-path /io/github/brsnippe/AgentUsage \
    --method io.github.brsnippe.AgentUsage.PlaySound "$1" >/dev/null 2>&1 && echo played || echo failed
}

# The color an actor is drawn in, as rrggbb.
color_of() {
  shell "(() => {
      const color = $1.get_theme_node().get_foreground_color();
      return [color.red, color.green, color.blue].map(value => value.toString(16).padStart(2, '0')).join('');
    })()"
}

finish() {
  kill "$shell_pid" 2>/dev/null
  echo
  if ((failures)); then
    echo "--- install.log"
    cat "$OUT/install.log"
    echo "--- GNOME Shell's errors"
    grep -A12 "JS ERROR" "$OUT/gnome-shell.log"
    echo
    echo "$failures failed"
    exit 1
  fi
  echo "all passed"
}

export XDG_CURRENT_DESKTOP=ubuntu:GNOME XDG_SESSION_TYPE=wayland

# ---- install, then log in: GNOME only loads extensions when it starts
"$ROOT/install.sh" >"$OUT/install.log" 2>&1
check "install.sh succeeds" "$?" "0"
check "it enables the extension for the next login" "$(gsettings get org.gnome.shell enabled-extensions | grep -c "'$UUID'")" "1"

gnome-shell --headless --virtual-monitor 1280x900 --wayland --no-x11 --unsafe-mode >"$OUT/gnome-shell.log" 2>&1 &
shell_pid=$!
for _ in $(seq 60); do
  [[ $(shell "'up'") == up ]] && break
  sleep 1
done
check "GNOME Shell starts, headless" "$(shell "'up'")" "up"
echo "     $(gnome-shell --version)"
trap finish EXIT

check "GNOME loads the extension, without errors" \
  "$(shell "(() => { const e = Main.extensionManager.lookup('$UUID'); return e.state + ' ' + (e.error || 'no error'); })()")" \
  "1 no error"
for _ in $(seq 20); do
  [[ $(shell "$INDICATOR._controller._queue.running === null") == true ]] && break
  sleep 0.5
done
check "with no usage yet, nothing in the top bar" "$(shell "$INDICATOR.visible")" "false"

# ---- a stand-in OpenCode, opened in a "terminal" set in the settings
mkdir -p ~/.local/bin
# (The session hooks ask it for its version; that doesn't open anything.)
printf '#!/bin/sh\n[ "$1" = --version ] && exit 0\necho "$@" >"%s/opened"\n' "$OUT" >~/.local/bin/opencode
chmod +x ~/.local/bin/opencode
gsettings --schemadir "$EXT_DIR/schemas" set org.gnome.shell.extensions.agent-usage terminal-command 'env AGENT_USAGE_TERMINAL=1 {command}'
gsettings --schemadir "$EXT_DIR/schemas" set org.gnome.shell.extensions.agent-usage terminal custom

# ---- the panel, with numbers in every section
for agent in claude codex; do
  cp "$ROOT/test/fake-collector" "$EXT_DIR/bin/agent-usage-$agent"
done
shell "$INDICATOR._controller.refresh()" >/dev/null
for _ in $(seq 20); do
  [[ $(shell "$INDICATOR._label.text") == "61%" ]] && break
  sleep 0.5
done
check "a refresh finds usage: the robot and the session limit appear" "$(shell "$INDICATOR.visible + ' ' + $INDICATOR._label.text")" "true 61%"

shell "$INDICATOR.menu.open()" >/dev/null
sleep 2
check "the panel opens" "$(shell "$INDICATOR.menu.isOpen")" "true"
check "the panel has every section" "$(shell "$INDICATOR._controller.actor.get_children().length")" "11"
check "the header has refresh, open, settings and switch-off buttons" \
  "$(shell "$INDICATOR._controller.actor.get_children()[0].get_children().map(child => child.accessible_name).filter(Boolean).join(', ')")" \
  "Refresh now (r), Open OpenCode in env, Settings, Switch off (q)"
check "the panel is in JetBrains Mono" "$(shell "$INDICATOR._controller.actor.get_theme_node().get_font().get_family().split(',')[0]")" "JetBrains Mono"
shot desktop-open
shot_menu panel-claude

shell "$INDICATOR._controller._select('codex')" >/dev/null
sleep 1
check "the Codex tab has the problem card with its sign-in button" \
  "$(shell "(() => {
      const labels = [];
      const walk = actor => {
        if (actor.get_label && typeof actor.get_label() === 'string') labels.push(actor.get_label());
        actor.get_children().forEach(walk);
      };
      walk($INDICATOR._controller.actor);
      return labels.includes('Sign in') ? 'yes' : labels.join('|');
    })()")" "yes"
shot_menu panel-codex
shell "$INDICATOR.menu.close()" >/dev/null

# ---- session colors: orange while a session waits for you, green once one
# is done, until the panel is opened. The robot pops and sounds each time.
gsettings --schemadir "$EXT_DIR/schemas" set org.gnome.shell.extensions.agent-usage session-sounds true
for _ in $(seq 20); do
  [[ $(shell "$INDICATOR._settings.get_boolean('session-sounds')") == true ]] && break
  sleep 0.25
done
# Every step of the robot's size, and the sounds it plays (played for real
# too, into a machine without speakers).
shell "(() => {
    const controller = $INDICATOR._controller, icon = $INDICATOR._icon;
    globalThis.agentUsageAlerts = {scales: [], sounds: []};
    icon.connect('notify::scale-x', () => agentUsageAlerts.scales.push(icon.scale_x));
    const play = controller._playSound.bind(controller);
    controller._playSound = alert => { agentUsageAlerts.sounds.push(alert); play(alert); };
  })()" >/dev/null
# The robot's size: how often it changed, how big it got, and where it is now.
pop_of() {
  shell "(() => {
      const scales = agentUsageAlerts.scales;
      return [scales.length > 4 ? 'animated' : 'instant', Math.max(1, ...scales).toFixed(1), $INDICATOR._icon.scale_x].join(' ');
    })()"
}
session_file waiting
for _ in $(seq 20); do
  [[ $(shell "$INDICATOR._icon.has_style_class_name('agent-usage-waiting')") == true ]] && break
  sleep 0.25
done
check "a session waiting for you turns the robot orange" "$(color_of "$INDICATOR._icon")" "ffa066"
check "and leaves the number as it was" "$(shell "$INDICATOR._label.text + ' ' + $INDICATOR._label.has_style_class_name('agent-usage-waiting')")" "61% false"
sleep 1
# GNOME switches animations off without a graphics card, as here.
check "with animations off, the pop is instant: the robot stays its size" \
  "$(shell "imports.gi.St.Settings.get().enable_animations") $(pop_of)" "false instant 1.5 1"
check "and it plays the waiting sound" "$(shell "agentUsageAlerts.sounds.join(' ')")" "waiting"
shot_actor topbar-waiting "$INDICATOR"
# What the pop looks like at its biggest.
shell "$INDICATOR._icon.set_scale(1.5, 1.5)" >/dev/null
sleep 0.3
shot_actor topbar-pop "$INDICATOR"
shell "$INDICATOR._icon.set_scale(1, 1); agentUsageAlerts.scales = []" >/dev/null
# Alerts closer together than 3 seconds merge. And animations on, as with a
# graphics card.
shell "imports.gi.St.Settings.get().uninhibit_animations()" >/dev/null
sleep 3
session_file ready
for _ in $(seq 20); do
  [[ $(shell "$INDICATOR._icon.has_style_class_name('agent-usage-ready')") == true ]] && break
  sleep 0.25
done
check "a finished turn turns it green" "$(color_of "$INDICATOR._icon")" "98bb6c"
sleep 1
check "and pops the robot: it grows to 1.5 and springs back" "$(pop_of)" "animated 1.5 1"
check "with the ready sound" "$(shell "agentUsageAlerts.sounds.join(' ')")" "waiting ready"
shell "imports.gi.St.Settings.get().inhibit_animations()" >/dev/null
shot_actor topbar-ready "$INDICATOR"
shell "$INDICATOR.menu.open()" >/dev/null
sleep 1
shell "$INDICATOR.menu.close()" >/dev/null
check "opening the panel clears the green" "$(shell "$INDICATOR._icon.has_style_class_name('agent-usage-ready')")" "false"
check "quietly" "$(shell "agentUsageAlerts.sounds.join(' ')")" "waiting ready"
rm -f "$SESSIONS/claude-smoke.json"
gsettings --schemadir "$EXT_DIR/schemas" reset org.gnome.shell.extensions.agent-usage session-sounds

# ---- the settings window's play buttons, as prefs.js presses them: GNOME
# Shell plays the sound, also with Sounds switched off
for _ in $(seq 20); do
  [[ $(shell "$INDICATOR._settings.get_boolean('session-sounds')") == false ]] && break
  sleep 0.25
done
check "the play buttons play each sound in GNOME Shell, also with Sounds off" \
  "$(play_sound waiting) $(play_sound ready) $(shell "agentUsageAlerts.sounds.join(' ')")" "played played waiting ready waiting ready"
check "and no other" "$(play_sound beep)" "failed"
check "which only the caller hears about" "$(grep -c "no sound called" "$OUT/gnome-shell.log")" "0"

# ---- clicks: right opens the agent, middle refreshes, left opens the panel
click 3
for _ in $(seq 20); do
  [[ -f $OUT/opened ]] && break
  sleep 0.25
done
check "a right click opens the agent, in the terminal from the settings, and not the panel" \
  "$([[ -f $OUT/opened ]] && echo opened) $(shell "$INDICATOR.menu.isOpen")" "opened false"

shell "(() => { const controller = $INDICATOR._controller; controller.refreshes = 0; controller.refresh = () => controller.refreshes++; })()" >/dev/null
click 2
check "a middle click refreshes, and not the panel" "$(shell "$INDICATOR._controller.refreshes + ' ' + $INDICATOR.menu.isOpen")" "1 false"
shell "delete $INDICATOR._controller.refresh" >/dev/null

click 1
check "a left click opens the panel" "$(shell "$INDICATOR.menu.isOpen")" "true"
shell "$INDICATOR.menu.close()" >/dev/null
sleep 0.5

# ---- with that switched off, a right click opens the panel instead
rm -f "$OUT/opened"
gsettings --schemadir "$EXT_DIR/schemas" set org.gnome.shell.extensions.agent-usage right-click-opens-agent false
for _ in $(seq 20); do
  [[ $(shell "$INDICATOR._settings.get_boolean('right-click-opens-agent')") == false ]] && break
  sleep 0.25
done
click 3
check "switched off, a right click opens the panel, not the agent" \
  "$(shell "$INDICATOR.menu.isOpen") $([[ -f $OUT/opened ]] && echo opened || echo 'not opened')" "true not opened"
shell "$INDICATOR.menu.close()" >/dev/null
gsettings --schemadir "$EXT_DIR/schemas" reset org.gnome.shell.extensions.agent-usage right-click-opens-agent

# ---- ⏻ asks, then switches the extension off until it's switched back on
shell "$INDICATOR.menu.open()" >/dev/null
sleep 1
shell "$(button 'Switch off (q)').emit('clicked', 1)" >/dev/null
sleep 0.5
check "⏻ asks first, in a card under the header" \
  "$(shell "$INDICATOR._controller.actor.get_children()[1] === $(button 'Cancel').get_parent().get_parent() && $(button 'Switch off') !== null")" "true"
shot_menu panel-switch-off
shell "$(button 'Cancel').emit('clicked', 1)" >/dev/null
sleep 0.5
check "Cancel takes the card away and leaves the panel open" "$(shell "($(button 'Cancel') === null) + ' ' + $INDICATOR.menu.isOpen")" "true true"
shell "$INDICATOR._controller.handleKey(imports.gi.Clutter.KEY_q)" >/dev/null
sleep 0.5
check "q asks too, with the focus on Switch off" "$(shell "global.stage.get_key_focus() === $(button 'Switch off')")" "true"
shell "$(button 'Switch off').emit('clicked', 1)" >/dev/null
for _ in $(seq 20); do
  [[ $(shell "Main.extensionManager.lookup('$UUID').state") == 2 ]] && break
  sleep 0.25
done
check "Switch off switches the extension off, and the robot goes" \
  "$(shell "Main.extensionManager.lookup('$UUID').state + ' ' + ('$UUID' in Main.panel.statusArea)")" "2 false"
# GNOME Shell's write reaches gsettings here a moment after it's done there.
for _ in $(seq 20); do
  [[ $(gsettings get org.gnome.shell disabled-extensions | grep -c "'$UUID'") == 1 ]] && break
  sleep 0.25
done
check "as the Extensions app would, so it stays off at the next login" \
  "$(gsettings get org.gnome.shell disabled-extensions | grep -c "'$UUID'")" "1"
check "a notification says how to switch it back on" \
  "$(shell "Main.messageTray.getSources().flatMap(source => source.notifications).some(n => n.title === 'Agent usage' && String(n.body).includes('gnome-extensions enable $UUID'))")" "true"
check "switched off, nothing plays the sounds" "$(play_sound ready)" "failed"
gnome-extensions enable "$UUID"
for _ in $(seq 20); do
  [[ $(shell "Main.panel.statusArea['$UUID']?.visible === true") == true ]] && break
  sleep 0.25
done
check "gnome-extensions enable brings it back" \
  "$(shell "Main.extensionManager.lookup('$UUID').state + ' ' + $INDICATOR.visible")" "1 true"
check "with the play buttons' sounds" "$(play_sound ready)" "played"

# ---- nothing went wrong along the way
check "GNOME Shell logged no JavaScript errors" "$(grep -c 'JS ERROR' "$OUT/gnome-shell.log")" "0"
check "and played the sounds without one" "$(grep -c 'could not play a sound' "$OUT/gnome-shell.log")" "0"
