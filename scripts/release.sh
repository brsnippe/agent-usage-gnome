#!/bin/bash
# Cut a release: scripts/release.sh 0.6.1
#
# Expects a "## 0.6.1" section in CHANGELOG.md (committed, or edited and not
# yet committed). Runs the tests, writes VERSION, commits, tags v0.6.1,
# pushes, and creates the GitHub release with that changelog section as its
# notes. Installs then pick it up with `agent-usage update`.

set -euo pipefail

die() {
  echo "release: $*" >&2
  exit 1
}

version="${1:-}"
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: scripts/release.sh X.Y.Z"
cd "$(dirname "${BASH_SOURCE[0]}")/.."

[[ $(git branch --show-current) == main ]] || die "release from main."
[[ -z $(git status --porcelain --untracked-files=no -- . ':!CHANGELOG.md') ]] ||
  die "commit or discard your changes first (only CHANGELOG.md may be uncommitted)."
git rev-parse -q --verify "refs/tags/v$version" >/dev/null && die "v$version already exists."
grep -q "^## $version\$" CHANGELOG.md || die "add a '## $version' section to CHANGELOG.md first."

echo "Running the tests …"
for test in test/*-test.js; do gjs -m "$test" >/dev/null || die "$test failed."; done
python3 test/claude-limits-test.py >/dev/null || die "test/claude-limits-test.py failed."
test/cli-test.sh >/dev/null || die "test/cli-test.sh failed."

echo "$version" >VERSION
git add VERSION CHANGELOG.md
git commit --quiet -m "Release v$version"
git tag -a "v$version" -m "v$version"
git push --quiet --follow-tags origin main
echo "Pushed v$version."

if command -v gh >/dev/null; then
  notes=$(awk -v heading="## $version" '$0 == heading {on = 1; next} on && /^## / {exit} on' CHANGELOG.md)
  gh release create "v$version" --title "v$version" --notes "$notes" >/dev/null && echo "Created the GitHub release."
fi
