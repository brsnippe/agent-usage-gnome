#!/bin/bash
# Inside a Linux Mint Docker image, as root: add what a Mint desktop has and
# the image lacks (Cinnamon, a virtual screen, a system bus, a normal user),
# then run the smoke test as that user on a copy of the checkout.
#
#   cinnamon/test/prepare-mint.sh SRC OUT
#   cinnamon/test/prepare-mint.sh --packages-only
#
# cinnamon/test/run-in-mint.sh runs this locally; CI runs it in its cinnamon
# job.

set -euo pipefail

PACKAGES=(cinnamon xvfb dbus-x11 dconf-gsettings-backend python3-gi jq fonts-jetbrains-mono libglib2.0-bin git)
if ! dpkg-query -W "${PACKAGES[@]}" >/dev/null 2>&1; then
  echo "Installing Cinnamon …"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq "${PACKAGES[@]}" >/dev/null
fi
[[ ${1:-} == --packages-only ]] && exit 0

src="$1"
out="$2"

# Cinnamon 6.8 (Mint 23) loads an applet's modules differently, and its
# packages can't be downloaded before it's released. With CINNAMON_LOADER=6.8
# the installed Cinnamon gets 6.8's loader: the two commits that changed it,
# fetched from Cinnamon's repository, minus the old loader's removal, which
# doesn't apply to 6.6 and isn't needed.
if [[ ${CINNAMON_LOADER:-} == 6.8 ]]; then
  echo "Putting Cinnamon 6.8's xlet loader on Cinnamon $(dpkg-query -W -f='${Version}' cinnamon) …"
  for commit in 406c075a 9517f868; do
    python3 -c 'import sys, urllib.request; sys.stdout.write(urllib.request.urlopen(sys.argv[1]).read().decode())' \
      "https://github.com/linuxmint/cinnamon/commit/$commit.diff"
  done >/tmp/cinnamon-6.8-loader.diff
  (cd /usr/share/cinnamon && git apply --exclude='js/misc/fileUtils.js' --include='js/*' /tmp/cinnamon-6.8-loader.diff)
  (cd / && git apply -p2 --include='usr/share/cinnamon/applets/*' /tmp/cinnamon-6.8-loader.diff)
fi

# logind and the rest live on the system bus; the panel listens there for
# suspend and resume.
mkdir -p /run/dbus
dbus-daemon --system --fork

id mint >/dev/null 2>&1 || useradd -m -s /bin/bash mint
rm -rf /home/mint/agent-usage
cp -r "$src" /home/mint/agent-usage
chown -R mint: /home/mint/agent-usage
mkdir -p "$out"
chmod 777 "$out"

runuser -u mint -- env HOME=/home/mint USER=mint LOGNAME=mint \
  /home/mint/agent-usage/cinnamon/test/smoke-test.sh "$out"
