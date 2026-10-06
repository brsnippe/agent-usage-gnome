#!/bin/bash
# Install Agent Usage for GNOME from git: clone it into
# ~/.local/share/agent-usage-gnome, check out the newest release, and run
# install.sh. Afterwards, `agent-usage update` keeps it current. On Linux
# Mint, install.sh installs the Cinnamon applet instead.
#
#   curl -fsSL https://raw.githubusercontent.com/brsnippe/agent-usage-gnome/main/get.sh | bash
#
# Or clone first and run it from the clone; it then installs from wherever
# that clone came from. AGENT_USAGE_REPO overrides where it clones from.
#
# On a Mac the same line installs the menu bar app instead: it downloads the
# newest release's app, without git, and lets the app's own agent-usage
# command install it into ~/Applications.

main() {
  set -euo pipefail

  if [[ $(uname -s) == Darwin ]]; then
    main_macos
    return
  fi

  local dest="${XDG_DATA_HOME:-$HOME/.local/share}/agent-usage-gnome"
  local repo="${AGENT_USAGE_REPO:-}"

  # Run from inside a clone: clone from wherever that clone came from.
  local here=""
  if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
    here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  fi
  if [[ -z $repo && -n $here ]] && git -C "$here" rev-parse --git-dir >/dev/null 2>&1; then
    repo=$(git -C "$here" remote get-url origin 2>/dev/null || true)
  fi
  repo="${repo:-https://github.com/brsnippe/agent-usage-gnome.git}"

  if ! command -v git >/dev/null; then
    echo "Installing git …"
    sudo apt-get update
    sudo apt-get install -y git
  fi

  if git -C "$dest" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Found $dest."
  else
    if [[ -e $dest ]]; then
      echo "$dest exists but isn't a git checkout; move it out of the way first." >&2
      exit 1
    fi
    echo "Cloning $repo …"
    mkdir -p "$(dirname "$dest")"
    git clone --quiet "$repo" "$dest"
  fi

  exec "$dest/bin/agent-usage" update --reinstall
}

# curl, unlike a browser, doesn't mark the download as coming from the
# internet, so macOS opens the app without asking about its developer.
main_macos() {
  local repo="${AGENT_USAGE_REPO:-brsnippe/agent-usage-gnome}"
  repo=$(sed -E 's#^(https://|ssh://git@|git@)github\.com[:/]##; s#\.git$##' <<<"$repo")
  local zip="${AGENT_USAGE_ZIP:-https://github.com/$repo/releases/latest/download/Agent-Usage-macOS.zip}"
  local tmp
  tmp=$(mktemp -d)

  echo "Downloading Agent Usage for macOS from github.com/$repo …"
  if ! curl -fL --progress-bar -o "$tmp/Agent-Usage-macOS.zip" "$zip"; then
    echo "Couldn't download $zip. Does the newest release have a macOS build?" >&2
    exit 1
  fi
  ditto -x -k "$tmp/Agent-Usage-macOS.zip" "$tmp"
  "$tmp/Agent Usage.app/Contents/Resources/bin/agent-usage" install "$tmp/Agent Usage.app"
  rm -rf "$tmp"
}

main "$@"
