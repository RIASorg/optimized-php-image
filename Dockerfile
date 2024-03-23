ARG PHP_VERSION=8.2
ARG PHP_BASE_IMAGE=php:${PHP_VERSION}-cli-bookworm
ARG BUILD_BASE_IMAGE=debian:bookworm-slim
ARG RUNTIME_BASE_IMAGE=bitnami/minideb:bookworm
ARG DEBIAN_FRONTEND=noninteractive

FROM $PHP_BASE_IMAGE as officialphp

FROM $BUILD_BASE_IMAGE as phpbuild

ARG PHP_VERSION=8.2
ENV PHP_VERSION=$PHP_VERSION
ENV PHP_INI_DIR=/usr/local/etc/php

ARG PHP_BUILD_DIR=/usr/src/php

ARG TZ=UTC

# Update locale
ARG LOCALE="C.UTF-8"
ARG LC_ALL=$LOCALE

# Add custom docker-php-source management using git
COPY ./docker-php-source /usr/local/bin/docker-php-source

# Disable recommends and suggests
RUN echo "APT::Install-Suggests "0";" >> /etc/apt/apt.conf.d/99local
RUN echo "APT::Install-Recommends "0";" >> /etc/apt/apt.conf.d/99local

RUN apt-get update

# Install basic dependencies for building
RUN apt-get -y install g++ gcc build-essential automake autoconf libtool bison re2c pkg-config git gnupg ca-certificates curl

# Install extension dependencies (less obvious ones: libonig => mbstring regex)
RUN apt-get -y install libsodium-dev libssl-dev libonig-dev libzip-dev libffi-dev libcurl4-openssl-dev zlib1g-dev libargon2-dev libreadline-dev \
    libsodium23 libonig5 libargon2-1 libzip4 libffi8

# Remove libxml2
RUN apt-get -y purge "libxml*"
# Build libxml2 without libicu to not inflate docker image size to 400MB
ARG LIBXML2_VERSION=2.12
RUN git clone https://github.com/GNOME/libxml2.git --branch=${LIBXML2_VERSION} --depth=1 && \
	cd libxml2 && \
	./autogen.sh && \
	./configure \
		--without-iconv \
		--with-iconv=no \
		--with-zlib \
		--without-icu \
		--with-icu=no \
		--with-lzma \
		--with-readline \
		--without-python \
		--with-python=no \
		--enable-static=no && \
	make -j "$(nproc)" && \
	make install && \
	cd .. && rm -rf ./libxml2
# Mark libxml as installed for APT
COPY ./build-fake-package.sh /usr/local/bin/build-fake-package
RUN mkdir -p /usr/local/etc/fake-packages && cd /usr/local/etc/fake-packages && build-fake-package libxml2 && dpkg -i libxml2-dummy*.deb

# Clone php-src
RUN docker-php-source extract

# https://github.com/docker-library/php/blob/master/8.2/bookworm/cli/Dockerfile#L51
ARG PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"
ARG PHP_CPPFLAGS="$PHP_CFLAGS"
ARG PHP_LDFLAGS="-Wl,-O1 -pie"

# Regenate configure script
RUN cd $PHP_BUILD_DIR && ./buildconf --force

# Create PHP config dir
RUN mkdir -p "$PHP_INI_DIR/conf.d"

# Configure PHP
RUN cd $PHP_BUILD_DIR && \
	export \
        CFLAGS="$PHP_CFLAGS" \
        CPPFLAGS="$PHP_CPPFLAGS" \
        LDFLAGS="$PHP_LDFLAGS" \
        PHP_BUILD_PROVIDER='Rias' \
        PHP_UNAME='Linux - Docker' && \
    ./configure \
    --enable-simplexml --enable-dom --enable-xmlwriter --enable-xmlreader --with-libxml \
    --without-pdo-sqlite --without-sqlite3 \
    --enable-sockets --enable-pcntl --enable-mbstring --enable-bcmath --enable-mysqlnd \
    --with-zip --with-password-argon2 --with-sodium --with-pdo-mysql --with-openssl --with-curl --with-ffi --with-zlib --with-mhash --with-pic --with-readline --with-mhash \
    --disable-cgi --disable-phpdbg \
    --enable-option-checking=fatal \
    --with-config-file-path="$PHP_INI_DIR" \
    --with-config-file-scan-dir="$PHP_INI_DIR/conf.d"

# Build PHP
RUN cd $PHP_BUILD_DIR && \
   	export \
           CFLAGS="$PHP_CFLAGS" \
           CPPFLAGS="$PHP_CPPFLAGS" \
           LDFLAGS="$PHP_LDFLAGS" \
           PHP_BUILD_PROVIDER='PicSea' \
           PHP_UNAME='Linux - Docker' && \
    make -j "$(nproc)"

# Delete archives and install left over files
RUN cd $PHP_BUILD_DIR && \
    find -type f -name '*.a' -delete; \
    make install; \
    cp -v php.ini-* "$PHP_INI_DIR/"

# Cleanup
RUN cd $PHP_BUILD_DIR && \
    find \
        /usr/local \
        -type f \
        -perm '/0111' \
        -exec sh -euxc ' \
            strip --strip-all "$@" || : \
        ' -- '{}' + && \
    make clean

FROM phpbuild as base

# Add scripts from official image since install-php-extensions needs them
COPY --from=officialphp /usr/local/bin/docker-php-ext-configure /usr/local/bin/docker-php-ext-configure
COPY --from=officialphp /usr/local/bin/docker-php-ext-enable /usr/local/bin/docker-php-ext-enable
COPY --from=officialphp /usr/local/bin/docker-php-ext-install /usr/local/bin/docker-php-ext-install

# Add custom scripts to facilitate easier usage
COPY ./php-settings-update.sh /usr/local/bin/php-settings-update
COPY ./keep.sh /usr/local/bin/keep
COPY ./keep-phpcli.sh /usr/local/bin/keep-phpcli
COPY ./package.sh /usr/local/bin/package

# Add install-php-extensions
COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/install-php-extensions

# Install basic extensions likely needed by most people (some of which are already included in PHP anyways)
RUN install-php-extensions opcache apcu bcmath sockets zip curl zlib mbstring ffi pcntl ctype iconv pcre tokenizer igbinary

# Change basic settings
RUN \
	mv /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini && \
	rm /usr/local/etc/php/php.ini-development && \
	php-settings-update 'date.timezone' "$TZ" && \
	php-settings-update 'apc.enable_cli' '1' && \
	php-settings-update 'apc.serializer' 'igbinary' && \
	php-settings-update 'opcache.enable' '1' && \
	php-settings-update 'opcache.enable_cli' '1' && \
	php-settings-update 'opcache.memory_consumption' '128' && \
	php-settings-update 'opcache.max_accelerated_files' '20000' && \
	php-settings-update 'opcache.interned_strings_buffer' '8'

# Package PHP up into /php
RUN \
	keep-phpcli && \
    keep /usr/local/bin/docker-php-ext-enable && \
    keep /usr/local/bin/php-settings-update

FROM base as packaged-for-building
# - Copy /usr/local/lib/php/build directory which is needed to build some extensions
# - Copy /usr/local/include/php directory which is needed to build some extensions
RUN \
    keep /usr/local/bin/keep-phpcli && \
    keep /usr/local/bin/package && \
    keep /usr/local/bin/keep && \
    keep /usr/local/bin/php-config && \
    keep /usr/local/bin/phpize && \
    keep /usr/local/bin/docker-php-ext-configure && \
    keep /usr/local/bin/docker-php-ext-install && \
    keep /usr/local/bin/docker-php-source && \
    keep /usr/local/bin/install-php-extensions && \
    keep "/usr/local/lib/php/build" && \
    keep "/usr/local/include/php" && \
    keep "/usr/local/etc/fake-packages" && \
    package "full"

FROM base as packaged-for-runtime

FROM packaged-for-runtime as packaged-for-runtime-scratch
RUN package "scratch"

FROM packaged-for-runtime as packaged-for-runtime-full
RUN package "full"

FROM $BUILD_BASE_IMAGE as full-builder
ARG PHP_VERSION=8.2
ENV PHP_VERSION=$PHP_VERSION
COPY --from=packaged-for-building /php/. /
# Install dependencies for building more extensions
RUN dpkg -i /usr/local/etc/fake-packages/*.deb && apt-get update && apt-get install -y build-essential autoconf automake git pkg-config ca-certificates

FROM scratch as scratch-builder
ARG PHP_VERSION=8.2
ENV PHP_VERSION=$PHP_VERSION
COPY --from=packaged-for-building /php/. /

FROM $RUNTIME_BASE_IMAGE as full-runtime
ARG PHP_VERSION=8.2
ENV PHP_VERSION=$PHP_VERSION
COPY --from=packaged-for-runtime-full /php/. /

FROM scratch as scratch-runtime
COPY --from=packaged-for-runtime-scratch /php /php
