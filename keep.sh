#!/usr/bin/env sh

set -e

printf "%s\n" "$1" >> /usr/local/FILES_TO_KEEP

# https://unix.stackexchange.com/a/85261
ldd "$1" 2>/dev/null | awk 'NF == 4 {print $3}; NF == 2 {print $1}' >> /usr/local/FILES_TO_KEEP
