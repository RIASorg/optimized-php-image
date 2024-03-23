#!/usr/bin/env sh

set -e

apt-get -y install equivs
echo "Package: $1-dummy\nProvides: $1\nDescription: fake" > "$1"-dummy.ctl
equivs-build "$1"-dummy.ctl
