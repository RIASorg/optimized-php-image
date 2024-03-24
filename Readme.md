# Optimized PHP Docker Image

This is a (collection of) docker image(s) I've cooked up that are optimized for smaller runtime Docker images.  
After checking out a lot of images on Github, Docker and the official images, 
I was dismayed when I realized they were all significantly larger than they needed to be.  
These images here contain a number of "optimizations" to reduce their final size by orders of magnitude (400MB vs 40MB).

## Usage

There are a total of 4 tags that represent different scenarios these may be used in.

### Full-Builder
`docker pull ghcr.io/riasorg/optimized-php-image:latest-full-builder`

This image not only contains the PHP-CLI, but is also based on Debian Bookworm and contains all scripts
and other files necessary to install extensions, or do other stuff with it.

Once you've got everything sorted out, you can prepare the final PHP package by calling `keep-phpcli && package "scratch"`.
This will package the php-cli, php extensions, and all needed shared libraries up into the directory `/php`
which can then be copied over to your final image, for example

```dockerfile
FROM ghcr.io/riasorg/optimized-php-image:latest-full-builder as my-builder

# Install additional extensions
RUN install-php-extensions rdkafka

# Package the PHP CLI and extensions up for a scatch environment
RUN keep-phpcli && package "scratch"

FROM scratch as final
COPY --from=my-builder /php/. /
```

### Scratch-Builder
`docker pull ghcr.io/riasorg/optimized-php-image:latest-scratch-builder`

This image, in comparison to the full builder, contains all necessary tools to build extensions and package the php runtime,
but is instead based on `scratch`. You can use it in an image of your choice, for example:

````dockerfile
FROM debian:bookworm as my-builder
COPY --from=ghcr.io/riasorg/optimized-php-image:latest-scratch-builder /. /

# Install fake packages
RUN dpkg -i /usr/local/etc/fake-packages/*.deb

# Install additional extensions
RUN install-php-extensions rdkafka

# Package the PHP CLI and extensions and other things up for a scatch environment
RUN keep-phpcli && keep "/bin/sh" && keep "/var/www" && package "scratch"

FROM scratch as final
COPY --from=my-builder /php/. /
````

### Full-Runtime
`docker pull ghcr.io/riasorg/optimized-php-image:latest-full-runtime`

This image does not contain any of the scripts or other files needed to build additional PHP extensions.  
It's intended for those that need a readymade image, do not need any other extensions, and cannot use `scratch`.  
It is based on `bitnami/minideb:bookworm`

### Scratch-Runtime
`docker pull ghcr.io/riasorg/optimized-php-image:latest-scratch-runtime`

Similar to the previous image, this cannot be used to build additional extensions.  
Instead, it's a runtime image based on `scratch` and thus only(!) includes the php-cli and the shared libraries for it.

## Scripts

This repo, and the `*-builder` images, contain some scripts that make the interaction with the PHP ecosystem a lot easier.
In particular there are:

- `keep $file_or_directory`: adds `$file_or_directory` to a list of files to keep for packaging and runs `ldd` on it to add all the shared libraries to the list as well
- `keep-phpcli`: calls `keep` on the php binary and all extensions
- `php-settings-update $setting $value`: sets `$setting` to `$value` in the php config
- `docker-php-source (extract|delete)`: Modified version of the official script to use `git` instead
- `build-fake-package $name`: Uses `equivs` to build a fake debian package. Is used here for libxml2
- `install-php-extensions`: Ships with the great `mlocati/php-extension-installer` script collection


## Detailed Changes
- A custom libxml2 build without libicu
- A custom PHP-CLI build without phpdbg, php-cgi, libphp or any of the other things the official image comes with
- No built-in libsqlite3 support in PHP
- A sensible base image without giant libraries that aren't actually needed
- Custom scripts to facilitate easier usage
- A final runtime image based on `scratch` (and actually working)
- No complicated statically built PHP runtime, instead Docker is used to make it static-ish. This also improves compatibility with extensions
- Sensible default, such as enabled OPCache, igbinary as apc serializer, and UTC as timezone

## Stuff to know
- Why the argument to `keep`? Depending on whether the package is intended for a Linux distro or `scratch` certain files need to be moved
as otherwise Docker, Kaniko, Linux or whoever would complain about a missing directory, in particular /lib and /lib64
since those are usually symlinked and would be overwritten otherwise
- Why `COPY /php/. /`? If you use `/.` then only files that are not present in the destination are copied over.
This is in particular necessary for Kaniko and other more finnicky image builders
- Why `bitnami/minideb` for the full runtime? In comparison to even the `debian:bookworm-slim` image the final image size is ~120MB vs ~400MB
