#!/bin/bash
# Run with: cinnamon/test/run-in-mint.sh [release] [snapshot folder]
#
# The smoke test in Linux Mint's own Docker image (linuxmintd/<release>-amd64,
# mint22.3 by default), as the cinnamon job in CI runs it. Screenshots of the
# panel and the logs land in cinnamon/snapshots/<release>.
#
# mint22.3-loader6.8 is Mint 22.3 with Cinnamon 6.8's way of loading applets
# (see prepare-mint.sh), standing in for Mint 23 until it's out.
#
# The first run installs Cinnamon in the image and keeps the result as
# agent-usage-test:<release>, so later runs start in seconds.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
release="${1:-mint22.3}"
out="${2:-$ROOT/cinnamon/snapshots/$release}"
mkdir -p "$out"
out=$(cd "$out" && pwd)

base="${release%-loader6.8}"
loader=""
[[ $release == *-loader6.8 ]] && loader=6.8
image="agent-usage-test:$base"

if ! docker image inspect "$image" >/dev/null 2>&1; then
  container="agent-usage-prepare-$base"
  docker rm -f "$container" >/dev/null 2>&1 || true
  docker run --name "$container" -v "$ROOT:/src:ro" "linuxmintd/$base-amd64" \
    bash /src/cinnamon/test/prepare-mint.sh --packages-only
  docker commit "$container" "$image" >/dev/null
  docker rm "$container" >/dev/null
fi

docker run --rm -e CINNAMON_LOADER="$loader" -v "$ROOT:/src:ro" -v "$out:/out" "$image" \
  bash /src/cinnamon/test/prepare-mint.sh /src /out
