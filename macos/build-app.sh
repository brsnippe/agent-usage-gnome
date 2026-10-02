#!/bin/bash
# Build "Agent Usage.app" into macos/build/: one binary for Apple silicon and
# Intel, the icons and fonts from Resources/, and the collectors from
# agent-usage@local/bin (the same files the GNOME extension uses). Signed
# ad hoc, which Apple silicon requires and needs no Apple account.
#
#   macos/build-app.sh            # build/Agent Usage.app
#   macos/build-app.sh --zip      # and build/Agent-Usage-macOS.zip

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

version=$(cat ../VERSION)
app="build/Agent Usage.app"
flags=(-c release --arch arm64 --arch x86_64 --product AgentUsage)

swift build "${flags[@]}"
bin=$(swift build "${flags[@]}" --show-bin-path)

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/bin" "$app/Contents/Resources/Fonts"
cp "$bin/AgentUsage" "$app/Contents/MacOS/AgentUsage"
sed "s/@VERSION@/$version/g" Resources/Info.plist >"$app/Contents/Info.plist"
cp Resources/Icons/*.pdf "$app/Contents/Resources/"
cp Resources/Fonts/*.ttf Resources/Fonts/OFL.txt "$app/Contents/Resources/Fonts/"
cp ../agent-usage@local/bin/agent-usage-claude ../agent-usage@local/bin/agent-usage-codex "$app/Contents/Resources/bin/"
chmod 755 "$app/Contents/Resources/bin/"*

codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict "$app"
lipo -info "$app/Contents/MacOS/AgentUsage"
echo "Built $app ($version)."

if [[ ${1:-} == --zip ]]; then
  # ditto keeps the permissions and the signature intact; zip -r can lose them.
  (cd build && rm -f Agent-Usage-macOS.zip && ditto -c -k --keepParent "Agent Usage.app" Agent-Usage-macOS.zip)
  echo "Zipped build/Agent-Usage-macOS.zip."
fi
