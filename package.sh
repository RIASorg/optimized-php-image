#!/usr/bin/env sh

set -e

mkdir -p /php

# - Copy all dependencies explictly identified
while read -r in; do cp -Lr --parents --preserve=links "$in" /php/ 2>/dev/null || :; done < /usr/local/FILES_TO_KEEP

if [ "$1" == "scratch" ]; then
  printf "Packaging for scratch"
  # OPCache or APCu need /tmp available for some kind of lock (???)
  mkdir -p /php/tmp

  # A lot of extensions (for example, rdkafka) will need the certificates locally available
  # Since they are fairly small overall, we can copy them over regardless of extension
  if [-d /etc/ssl/certs]; then
    cp -Lr --parents --preserve=links /etc/ss/certs /php/
  fi
else
  printf "Packaging for Linux distro"
  # - Move /lib and /lib64, since those are actually symbolic links that are present on basically every Linux installation and overwriting them is a big no-no
  mkdir -p /php/usr/lib && mkdir -p /php/usr/lib64
  mv /php/lib/* /php/usr/lib/ && mv /php/lib64/* /php/usr/lib64/
  rm -rf /php/lib && rm -rf /php/lib64
fi
