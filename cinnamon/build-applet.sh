#!/bin/bash
# Assemble the Cinnamon applet in DEST: its own files from
# cinnamon/agent-usage@local, the collectors, session hooks, icons, sounds
# and stylesheet it shares with the GNOME extension, and the shared modules
# rewritten for Cinnamon's module system.
#
#   cinnamon/build-applet.sh DEST [VERSION]
#
# VERSION goes into metadata.json, where the update check and Cinnamon's
# About dialog read it, and into the settings window.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SHARED="$ROOT/agent-usage@local"
OWN="$ROOT/cinnamon/agent-usage@local"
# The shared ES modules the applet loads, converted.
MODULES=(panel sessions terminals updates usage versions)

dest="${1:?usage: build-applet.sh DEST [VERSION]}"
version="${2:-}"

rm -rf "$dest"
mkdir -p "$dest/bin"
cp "$OWN/applet.js" "$OWN/icon.png" "$dest/"
cp -r "$SHARED/icons" "$SHARED/hooks" "$SHARED/sounds" "$dest/"
cp "$SHARED"/bin/agent-usage-* "$dest/bin/"
chmod +x "$dest"/bin/* "$dest/hooks/agent-usage-session"
cat "$SHARED/stylesheet.css" "$OWN/stylesheet.css" >"$dest/stylesheet.css"

for module in "${MODULES[@]}"; do
  python3 "$ROOT/cinnamon/esm-to-cinnamon.py" "$SHARED/$module.js" >"$dest/$module.js"
done
# Every module the applet or a converted module loads has to be built too.
for wanted in $(grep -ohE "load\('[a-z-]+'\)" "$dest"/*.js | sed -E "s/load\('(.*)'\)/\1/" | sort -u); do
  if [[ ! -f $dest/$wanted.js ]]; then
    echo "build-applet: $wanted.js is loaded but not built; add it to MODULES" >&2
    exit 1
  fi
done

python3 - "$OWN" "$dest" "$version" <<'PY'
import json, sys

own, dest, version = sys.argv[1:]
with open(f"{own}/metadata.json", encoding="utf-8") as f:
    metadata = json.load(f)
with open(f"{own}/settings-schema.json", encoding="utf-8") as f:
    schema = json.load(f)
if version:
    metadata["version"] = version
    schema["version"]["description"] = (
        f"Version: v{version}. The panel's bottom line says when a newer one is out.")
for name, data in (("metadata.json", metadata), ("settings-schema.json", schema)):
    with open(f"{dest}/{name}", "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
PY
