#!/usr/bin/env bash

set -xe

echo "$1=$2" | tee /usr/local/etc/php/conf.d/${1@Q}.ini > /dev/null
