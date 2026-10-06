#!/bin/bash
# Run with: test/gnome/run-in-ubuntu.sh [release] [snapshot folder]
#
# The GNOME smoke test in Ubuntu's Docker image (ubuntu:<release>, 24.04 by
# default), as the gnome job in CI runs it. Screenshots of the panel and the
# logs land in test/gnome/snapshots/<release>.
#
# The first run installs GNOME Shell in the image and keeps the result as
# agent-usage-test:ubuntu<release>, so later runs start in seconds.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
release="${1:-24.04}"
out="${2:-$ROOT/test/gnome/snapshots/$release}"
mkdir -p "$out"
out=$(cd "$out" && pwd)
image="agent-usage-test:ubuntu$release"

if ! docker image inspect "$image" >/dev/null 2>&1; then
  container="agent-usage-prepare-ubuntu$release"
  docker rm -f "$container" >/dev/null 2>&1 || true
  docker run --name "$container" -v "$ROOT:/src:ro" "ubuntu:$release" \
    bash /src/test/gnome/prepare-ubuntu.sh --packages-only
  docker commit "$container" "$image" >/dev/null
  docker rm "$container" >/dev/null
fi

docker run --rm -v "$ROOT:/src:ro" -v "$out:/out" "$image" \
  bash /src/test/gnome/prepare-ubuntu.sh /src /out
