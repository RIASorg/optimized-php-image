#!/usr/bin/env sh

set -e

keep /usr/local/bin/php
keep "$PHP_INI_DIR"
find "/usr/local/lib/php/extensions" -name "*.so" -exec keep {} \;
