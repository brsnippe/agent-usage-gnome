#!/bin/bash
# Run with: test/cli-test.sh
#
# The git install flow end to end, against a local bare repository standing in
# for GitHub: get.sh, `agent-usage version / latest / update / uninstall`.
# GNOME's tools are replaced by stand-ins, so this runs anywhere with git,
# jq and python3.

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d /tmp/agent-usage-cli-test.XXXXXX)
trap 'rm -rf "$T"' EXIT
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

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

# --- a "GitHub" with release v0.6.0
git init --quiet --bare --initial-branch=main "$T/remote.git"
git init --quiet --initial-branch=main "$T/work"
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$ROOT" ls-files -z | (cd "$ROOT" && xargs -0 cp --parents -t "$T/work")
else
  (cd "$ROOT" && find . -type f -not -path './.git/*' -not -name '*.pyc' -print0 | xargs -0 cp --parents -t "$T/work")
fi
release() {
  echo "$1" >"$T/work/VERSION"
  git -C "$T/work" add -A
  git -C "$T/work" commit --quiet -m "Release v$1"
  git -C "$T/work" tag "v$1"
  git -C "$T/work" push --quiet --tags "$T/remote.git" main
}
release 0.6.0
git -C "$T/work" tag not-a-release
git -C "$T/work" push --quiet --tags "$T/remote.git" main

# --- stand-ins for GNOME's tools, and an empty home
mkdir -p "$T/stubs" "$T/settings" "$T/home"
printf '#!/bin/bash\necho "GNOME Shell 46.0"\n' >"$T/stubs/gnome-shell"
cat >"$T/stubs/gsettings" <<EOF
#!/bin/bash
store="\${STUB_SETTINGS:-$T/settings}"
[[ \$1 == --schemadir ]] && exit 0
case \$1 in
  get) if [[ -f \$store/\$3 ]]; then cat "\$store/\$3"; elif [[ \$3 == disable-user-extensions ]]; then echo false; else echo "@as []"; fi ;;
  set) printf '%s\n' "\$4" >"\$store/\$3" ;;
esac
EOF
printf '#!/bin/bash\nexit 0\n' >"$T/stubs/gnome-extensions"
printf '#!/bin/bash\nprintf "install ok installed"\n' >"$T/stubs/dpkg-query"
# Linux Mint's: Cinnamon, and its D-Bus interface, which only records calls.
printf '#!/bin/bash\necho "Cinnamon 6.6.4"\n' >"$T/stubs/cinnamon"
printf '#!/bin/bash\necho "$*" >>"%s"\n' "$T/gdbus.log" >"$T/stubs/gdbus"
chmod +x "$T/stubs"/*

H="$T/home"
run() {
  env HOME="$H" XDG_DATA_HOME="$H/.local/share" XDG_CONFIG_HOME="$H/.config" XDG_STATE_HOME="$H/.local/state" \
    XDG_CACHE_HOME="$H/.cache" XDG_CURRENT_DESKTOP=ubuntu:GNOME XDG_SESSION_TYPE=x11 \
    PATH="$T/stubs:$PATH" AGENT_USAGE_REPO="$T/remote.git" "$@"
}
EXT="$H/.local/share/gnome-shell/extensions/agent-usage@local"
CLONE="$H/.local/share/agent-usage-gnome"
CLI="$H/.local/bin/agent-usage"
installed() { jq -r '.["version-name"]' "$EXT/metadata.json" 2>/dev/null; }

# --- first install
run bash "$ROOT/get.sh" >"$T/get.log" 2>&1
check "get.sh succeeds" "$?" "0"
check "it installs the newest release" "$(installed)" "0.6.0"
check "from a clone in ~/.local/share/agent-usage-gnome" "$(git -C "$CLONE" describe --tags --match 'v[0-9]*' 2>/dev/null)" "v0.6.0"
check "the extension knows where it came from" "$(cat "$EXT/source" 2>/dev/null)" "$CLONE"
check "the agent-usage command is on the PATH" "$(readlink "$CLI")" "$CLONE/bin/agent-usage"
check "the source metadata keeps no version-name" "$(jq -r '.["version-name"] // "none"' "$CLONE/agent-usage@local/metadata.json")" "none"

check "latest ignores tags that aren't releases" "$(run "$CLI" latest)" "0.6.0"
check "version says up to date" "$(run "$CLI" version)" "installed: 0.6.0
newest:    0.6.0 (up to date)"
check "update does nothing when current" "$(run "$CLI" update 2>&1 | tail -1)" "Already up to date: 0.6.0."

# --- a new release appears
release 0.6.1
check "latest sees the new release" "$(run "$CLI" latest)" "0.6.1"
check "version points at update" "$(run "$CLI" version | tail -1)" "newest:    0.6.1 (run: agent-usage update)"
run "$CLI" update >"$T/update.log" 2>&1
check "update succeeds" "$?" "0"
check "update installs it" "$(installed)" "0.6.1"
check "the clone sits on the new tag" "$(git -C "$CLONE" describe --tags)" "v0.6.1"

# --- the main branch, for testing
echo "# work in progress" >>"$T/work/README.md"
git -C "$T/work" commit --quiet -am "Work in progress"
git -C "$T/work" push --quiet "$T/remote.git" main
run "$CLI" update --main >/dev/null 2>&1
check "update --main installs a dev build" "$(installed)" "0.6.1-dev+$(git -C "$T/work" rev-parse --short HEAD)"
run "$CLI" update >/dev/null 2>&1
check "and plain update goes back to the newest release" "$(installed)" "0.6.1"

# --- a clone with local edits is left alone
echo "local edit" >>"$CLONE/README.md"
check "update refuses to overwrite local changes" "$(run "$CLI" update 2>&1 | tail -1)" \
  "agent-usage: $CLONE has local changes; commit or discard them first."
git -C "$CLONE" checkout --quiet -- README.md

# --- get.sh again on an existing install just updates it
run bash "$ROOT/get.sh" >/dev/null 2>&1
check "get.sh on an existing install reinstalls the newest release" "$(installed)" "0.6.1"

# --- uninstall
run "$CLI" uninstall >"$T/uninstall.log" 2>&1
check "uninstall succeeds" "$?" "0"
check "and removes the extension, the clone and the command" \
  "$([[ -e $EXT ]] && echo ext) $([[ -e $CLONE ]] && echo clone) $([[ -L $CLI ]] && echo cli)" "  "

# --- Linux Mint: the same get.sh in a Cinnamon session installs the applet
M="$T/mint"
MS="$T/mint-settings"
mkdir -p "$M" "$MS"
MINT_PANEL="'panel1:left:0:menu@cinnamon.org:0', 'panel1:right:0:systray@cinnamon.org:3', 'panel1:right:1:xapp-status@cinnamon.org:4', 'panel1:right:2:calendar@cinnamon.org:12'"
echo "[$MINT_PANEL]" >"$MS/enabled-applets"
echo 42 >"$MS/next-applet-id"
mint() {
  env HOME="$M" XDG_DATA_HOME="$M/.local/share" XDG_CONFIG_HOME="$M/.config" XDG_STATE_HOME="$M/.local/state" \
    XDG_CACHE_HOME="$M/.cache" XDG_CURRENT_DESKTOP=X-Cinnamon XDG_SESSION_TYPE=x11 STUB_SETTINGS="$MS" \
    PATH="$T/stubs:$PATH" AGENT_USAGE_REPO="$T/remote.git" "$@"
}
APPLET="$M/.local/share/cinnamon/applets/agent-usage@local"
MCLONE="$M/.local/share/agent-usage-gnome"
MCLI="$M/.local/bin/agent-usage"
applet_version() { jq -r '.version' "$APPLET/metadata.json" 2>/dev/null; }

mint bash "$ROOT/get.sh" >"$T/mint-get.log" 2>&1
check "on Cinnamon, get.sh succeeds" "$?" "0"
check "it installs the applet, not the extension" \
  "$(applet_version) $([[ -e $M/.local/share/gnome-shell ]] && echo extension)" "0.6.1 "
check "the applet knows where it came from" "$(cat "$APPLET/source" 2>/dev/null)" "$MCLONE"
check "it's built: Cinnamon's files, the converted modules, the collectors" \
  "$(cd "$APPLET" 2>/dev/null && ls applet.js bin/agent-usage-claude panel.js settings-schema.json usage.js 2>&1 | tr '\n' ' ')" \
  "applet.js bin/agent-usage-claude panel.js settings-schema.json usage.js "
check "its settings window shows the version" "$(jq -r '.version.description' "$APPLET/settings-schema.json" 2>/dev/null)" \
  "Version: v0.6.1. The panel's bottom line says when a newer one is out."
check "a first install adds it to the panel, first in the zone with the status icons" "$(cat "$MS/enabled-applets")" \
  "[$MINT_PANEL, 'panel1:right:-1:agent-usage@local:42']"
check "with the next free instance id" "$(cat "$MS/next-applet-id")" "43"
check "agent-usage version reads the applet's version" "$(mint "$MCLI" version | head -1)" "installed: 0.6.1"
check "diagnose reports on the applet" "$(mint "$MCLI" diagnose 2>&1 | grep '^installed:')" "installed: yes, version 0.6.1"

release 0.6.2
: >"$T/gdbus.log"
mint "$MCLI" update >"$T/mint-update.log" 2>&1
check "on Cinnamon, update installs the new release" "$(applet_version)" "0.6.2"
check "and has Cinnamon reload the applet, without a logout" "$(grep -c 'org.Cinnamon.ReloadXlet agent-usage@local APPLET' "$T/gdbus.log")" "1"
check "without adding it to the panel a second time" "$(grep -o 'agent-usage@local' "$MS/enabled-applets" | wc -l)" "1"

echo "[$MINT_PANEL]" >"$MS/enabled-applets"
: >"$T/gdbus.log"
mint "$MCLI" update --reinstall >/dev/null 2>&1
check "an update leaves an applet someone took off the panel off it" \
  "$(grep -c 'agent-usage@local' "$MS/enabled-applets") $(grep -c ReloadXlet "$T/gdbus.log")" "0 0"

echo "[$MINT_PANEL, 'panel1:right:-1:agent-usage@local:43']" >"$MS/enabled-applets"
mkdir -p "$M/.config/cinnamon/spices/agent-usage@local"
echo '{}' >"$M/.config/cinnamon/spices/agent-usage@local/43.json"
mint "$MCLI" uninstall --purge >"$T/mint-uninstall.log" 2>&1
check "on Cinnamon, uninstall succeeds" "$?" "0"
check "and takes the applet off the panel" "$(cat "$MS/enabled-applets")" "[$MINT_PANEL]"
check "and removes the applet, its settings, the clone and the command" \
  "$([[ -e $APPLET ]] && echo applet) $([[ -e $M/.config/cinnamon/spices/agent-usage@local ]] && echo settings) $([[ -e $MCLONE ]] && echo clone) $([[ -L $MCLI ]] && echo cli)" \
  "   "

if ((failures)); then
  echo
  echo "--- get.log"; cat "$T/get.log"
  echo "--- update.log"; cat "$T/update.log"
  echo "--- mint-get.log"; cat "$T/mint-get.log"
  echo "--- mint-update.log"; cat "$T/mint-update.log"
  echo
  echo "$failures failed"
  exit 1
fi
echo
echo "all passed"
