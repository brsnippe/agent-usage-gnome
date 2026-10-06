#!/bin/bash
# Build "Agent Usage.app" into macos/build/: one binary for Apple silicon and
# Intel, the icons and fonts from Resources/, and the collectors, session
# hooks and sounds from agent-usage@local (the same files the GNOME extension
# uses).
# Signed ad hoc, which Apple silicon requires and needs no Apple account.
#
#   macos/build-app.sh            # build/Agent Usage.app
#   macos/build-app.sh --zip      # and build/Agent-Usage-macOS.zip

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

version=$(cat ../VERSION)
# As install.sh labels GNOME installs: the plain version on its release tag,
# VERSION-dev+<commit> anywhere else, so a test build never looks newer than
# the release it leads up to.
label="$version"
tag=$(git describe --tags --exact-match 2>/dev/null || true)
# A CI checkout of a tag may come without the tag object itself.
[[ ${GITHUB_REF_TYPE:-} == tag ]] && tag=$GITHUB_REF_NAME
if [[ $tag != "v$version" || -n $(git status --porcelain --untracked-files=no) ]]; then
  label="$version-dev+$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi
# Where the update check looks for releases: this checkout's GitHub repository.
remote=$(git remote get-url origin 2>/dev/null || true)
repository=$(sed -nE 's#^(https://|ssh://git@|git@)github\.com[:/]([^/]+/[^/]+)$#\2#p' <<<"${remote%.git}")
repository=${repository:-${GITHUB_REPOSITORY:-brsnippe/agent-usage-gnome}}
app="build/Agent Usage.app"
flags=(-c release --arch arm64 --arch x86_64 --product AgentUsage)

swift build "${flags[@]}"
bin=$(swift build "${flags[@]}" --show-bin-path)

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/bin" "$app/Contents/Resources/hooks" "$app/Contents/Resources/Fonts" "$app/Contents/Resources/Sounds"
cp "$bin/AgentUsage" "$app/Contents/MacOS/AgentUsage"
sed -e "s/@VERSION@/$version/g" -e "s/@VERSION_LABEL@/$label/g" -e "s#@REPOSITORY@#$repository#g" Resources/Info.plist >"$app/Contents/Info.plist"
cp Resources/Icons/*.pdf "$app/Contents/Resources/"
cp Resources/Fonts/*.ttf Resources/Fonts/OFL.txt "$app/Contents/Resources/Fonts/"
cp ../agent-usage@local/bin/agent-usage-claude ../agent-usage@local/bin/agent-usage-codex agent-usage "$app/Contents/Resources/bin/"
chmod 755 "$app/Contents/Resources/bin/"*
# The session colors' hooks, outside bin/: everything there is a collector.
cp ../agent-usage@local/hooks/agent-usage-session ../agent-usage@local/hooks/opencode-agent-usage.js "$app/Contents/Resources/hooks/"
chmod 755 "$app/Contents/Resources/hooks/agent-usage-session"
cp ../agent-usage@local/sounds/*.wav "$app/Contents/Resources/Sounds/"

codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict "$app"
lipo -info "$app/Contents/MacOS/AgentUsage"
echo "Built $app ($label, releases from $repository)."

if [[ ${1:-} == --zip ]]; then
  # ditto keeps the permissions and the signature intact; zip -r can lose them.
  (cd build && rm -f Agent-Usage-macOS.zip && ditto -c -k --keepParent "Agent Usage.app" Agent-Usage-macOS.zip)
  echo "Zipped build/Agent-Usage-macOS.zip."
fi
