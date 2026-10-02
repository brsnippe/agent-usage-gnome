#!/bin/bash
# Install Agent Usage for GNOME from git: clone it into
# ~/.local/share/agent-usage-gnome, check out the newest release, and run
# install.sh. Afterwards, `agent-usage update` keeps it current.
#
#   curl -fsSL https://raw.githubusercontent.com/brsnippe/agent-usage-gnome/main/get.sh | bash
#
# Or clone first and run it from the clone; it then installs from wherever
# that clone came from. AGENT_USAGE_REPO overrides where it clones from.

main() {
  set -euo pipefail

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

main "$@"
