#!/bin/bash
# Inside an Ubuntu Docker image, as root: add what an Ubuntu desktop has and
# the image lacks (GNOME Shell, a system bus with logind on it, a normal
# user), then run the GNOME smoke test as that user on a copy of the
# checkout.
#
#   test/gnome/prepare-ubuntu.sh SRC OUT
#   test/gnome/prepare-ubuntu.sh --packages-only
#
# test/gnome/run-in-ubuntu.sh runs this locally; CI runs it in its gnome job.

set -euo pipefail

PACKAGES=(gnome-shell dbus-x11 dconf-gsettings-backend python3-gi jq fonts-jetbrains-mono libglib2.0-bin git)
if ! dpkg-query -W "${PACKAGES[@]}" >/dev/null 2>&1; then
  echo "Installing GNOME Shell …"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq "${PACKAGES[@]}" >/dev/null
fi
[[ ${1:-} == --packages-only ]] && exit 0

src="$1"
out="$2"

mkdir -p /run/dbus
dbus-daemon --system --fork
python3 "$src/test/gnome/fake-logind.py" &
sleep 1

id ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu
rm -rf /home/ubuntu/agent-usage
cp -r "$src" /home/ubuntu/agent-usage
chown -R ubuntu: /home/ubuntu/agent-usage
mkdir -p "$out"
chmod 777 "$out"

runuser -u ubuntu -- env HOME=/home/ubuntu USER=ubuntu LOGNAME=ubuntu \
  /home/ubuntu/agent-usage/test/gnome/smoke-test.sh "$out"
