#!/usr/bin/env sh

set -xe

printf "%s=%s" "$1" "$2" > /usr/local/etc/php/conf.d/${1}.ini
