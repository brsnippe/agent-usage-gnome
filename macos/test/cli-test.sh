#!/bin/bash
# Run on a Mac, after macos/build-app.sh --zip: macos/test/cli-test.sh
#
# Installs, updates and uninstalls the app CI just built, through get.sh and
# the agent-usage command, in a throwaway home folder. The app itself isn't
# started (AGENT_USAGE_NO_OPEN), so the Mac's own login items stay as they are.

set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
zip="$root/macos/build/Agent-Usage-macOS.zip"
[[ -f $zip ]] || {
  echo "Build the app first: macos/build-app.sh --zip" >&2
  exit 1
}

failures=0
check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    failures=$((failures + 1))
  fi
}
contains() {
  grep -qF -- "$2" <<<"$1"
}

HOME=$(mktemp -d)
export HOME AGENT_USAGE_ZIP="file://$zip" AGENT_USAGE_NO_OPEN=1 PATH="$HOME/.local/bin:$PATH"
app="$HOME/Applications/Agent Usage.app"

out=$(bash "$root/get.sh" 2>&1)
check "get.sh installs the app into ~/Applications" test -x "$app/Contents/MacOS/AgentUsage"
check "with its collectors" test -x "$app/Contents/Resources/bin/agent-usage-claude"
check "and links the command" test "$(readlink "$HOME/.local/bin/agent-usage")" = "$app/Contents/Resources/bin/agent-usage"
check "the signature survives" codesign --verify --strict "$app"
check "no quarantine flag" test -z "$(xattr -p com.apple.quarantine "$app" 2>/dev/null)"
check "it says where it went" contains "$out" "Installed Agent Usage"

out=$(agent-usage version 2>&1)
check "version names the installed build" contains "$out" "installed: $(cat "$root/VERSION")"

out=$(agent-usage diagnose 2>&1)
check "diagnose reports the app" contains "$out" "version:    $(cat "$root/VERSION")"
check "diagnose finds the collectors" contains "$out" "agent-usage-claude"
check "diagnose checks the Keychain without printing it" contains "$out" 'keychain:   "Claude Code-credentials"'

touch "$app/stale-marker"
out=$(agent-usage update --reinstall 2>&1)
check "update replaces the app" test ! -e "$app/stale-marker"
check "and the command still works afterwards" agent-usage version

mkdir -p "$HOME/.local/state/omarchy/agents/usage" "$HOME/Library/Logs/AgentUsage"
echo '{"id": "claude"}' >"$HOME/.local/state/omarchy/agents/usage/claude.json"
agent-usage uninstall >/dev/null 2>&1
check "uninstall removes the app" test ! -e "$app"
check "and the command" test ! -L "$HOME/.local/bin/agent-usage"
check "but keeps the usage data" test -f "$HOME/.local/state/omarchy/agents/usage/claude.json"

bash "$root/get.sh" >/dev/null 2>&1
"$HOME/.local/bin/agent-usage" uninstall --purge >/dev/null 2>&1
check "--purge also removes the usage data" test ! -e "$HOME/.local/state/omarchy/agents/usage"
check "and the logs" test ! -e "$HOME/Library/Logs/AgentUsage"

echo
if ((failures == 0)); then echo "all passed"; else echo "$failures failed"; fi
exit $((failures > 0))
