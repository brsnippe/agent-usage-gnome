# Shared by the GNOME scripts (install.sh, uninstall.sh, diagnose.sh) and the
# Cinnamon ones (cinnamon/*.sh). Sourced, not run.

USAGE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/agents/usage"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
note() { printf '\033[33m  ! %s\033[0m\n' "$*"; }

# Installs the given apt packages if any are missing.
ensure_packages() {
  local missing=() package status
  for package in "$@"; do
    status=$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)
    [[ $status == "install ok installed" ]] || missing+=("$package")
  done
  if ((${#missing[@]})); then
    echo "  Installing: ${missing[*]}"
    sudo apt-get update
    sudo apt-get install -y "${missing[@]}"
  else
    echo "  All present."
  fi
}

# The version an install reports, and the update check compares: the release
# tag when installing one, otherwise VERSION marked as a development build.
# Sets VERSION_NAME, and FROM_GIT when $1 is a git checkout.
read_version() {
  local src="$1" tag
  VERSION_NAME=$(cat "$src/VERSION" 2>/dev/null || echo 0.0.0)
  FROM_GIT=false
  if git -C "$src" rev-parse --git-dir >/dev/null 2>&1; then
    FROM_GIT=true
    if tag=$(git -C "$src" describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null); then
      VERSION_NAME="${tag#v}"
    else
      VERSION_NAME="$VERSION_NAME-dev+$(git -C "$src" rev-parse --short HEAD)"
    fi
    [[ -z $(git -C "$src" status --porcelain --untracked-files=no) ]] || VERSION_NAME="$VERSION_NAME.dirty"
  fi
}

# One line per agent with usage, from the records the collectors wrote.
# Returns 1 when no agent has any.
summarize_usage() {
  local record summary found=1
  shopt -s nullglob
  for record in "$USAGE_DIR"/*.json; do
    summary=$(jq -r '
      def has_data: ([.totalPrompts, .totalSessions, .activeDays, .todayPrompts, .todaySessions] | map(. // 0) | add) > 0
        or ((.limits // []) | length) > 0 or .balance != null;
      select(has_data)
      | "  \(.name)\(if (.tierLabel // "") != "" then " · \(.tierLabel)" else "" end): "
        + ([.limits[]? | "\(.title // .label) \((.percent * 100) | round)%"] | if length > 0 then join(", ") else "no limits" end)
        + (if (.usageStatusText // "") != "" then "\n    ! \(.usageStatusText). \(.authHelpText // "")" else "" end)
    ' "$record" 2>/dev/null || true)
    if [[ -n $summary ]]; then
      echo "$summary"
      found=0
    fi
  done
  shopt -u nullglob
  return $found
}

# --purge: the usage data and caches the collectors wrote.
purge_usage_data() {
  local state_home="${XDG_STATE_HOME:-$HOME/.local/state}" cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
  # These folders keep Omarchy's names, and on an Omarchy machine they belong
  # to Omarchy's own bar widget.
  if [[ -d /usr/share/omarchy ]]; then
    echo "Omarchy is installed here and uses the same folders; leaving the usage data alone."
    return
  fi
  rm -rf "$state_home/omarchy/agents/usage" "$cache_home/omarchy/agent-usage"
  rmdir "$state_home/omarchy/agents" "$state_home/omarchy" "$cache_home/omarchy" 2>/dev/null || true
  echo "Deleted the collected usage data, caches and settings."
}

# diagnose: the records, and the Claude collector's limits checks.
print_usage_records() {
  local record limits_cache
  echo
  echo "== Usage records"
  ls -la "$USAGE_DIR" 2>&1
  for record in "$USAGE_DIR"/*.json; do
    [[ -f $record ]] || continue
    jq -c '{id, ready, tierLabel, usageStatusText, limits: [.limits[]? | {label, title, percent}], limitsFetchedAt, limitsStale, limitsNote, totalPrompts, todayTotalTokens, updatedAt}' "$record" 2>&1
  done

  echo
  echo "== Claude limits checks"
  limits_cache="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/agent-usage/claude-limits.json"
  if [[ -f $limits_cache ]]; then
    jq -r '"last good check: \(.fetchedAtMs / 1000 | strflocaltime("%H:%M:%S"))",
      (if .backoffUntilMs then "rate limited: paused \(.backoffSeconds)s, until \(.backoffUntilMs / 1000 | strflocaltime("%H:%M:%S"))" else "rate limited: no" end)' "$limits_cache" 2>&1
  else
    echo "no checks yet"
  fi
}

# diagnose: where an install came from, and the newest release there.
print_source() {
  local source_file="$1" source_dir
  if [[ -f $source_file ]]; then
    source_dir=$(cat "$source_file")
    echo "source: $source_dir ($(git -C "$source_dir" remote get-url origin 2>/dev/null || echo "no remote"))"
    echo "newest release: $("$source_dir/bin/agent-usage" latest 2>&1)"
  else
    echo "source: not a git install, so no updates"
  fi
}
