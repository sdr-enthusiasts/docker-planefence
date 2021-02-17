
FROM debian:stable-slim

ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Copy needs to be here to prevent github actions from failing.
# SSL Certs are pre-loaded into the rootfs via a job in github action:
# See: "Copy CA Certificates from GitHub Runner to Image rootfs" in deploy.yml
COPY rootfs/ /

# Copy the planefence program files in place:
COPY noisecapt/ /noisecapt

RUN set -x && \
# define packages needed for installation and general management of the container:
    TEMP_PACKAGES=() && \
    KEPT_PACKAGES=() && \
    KEPT_PIP_PACKAGES=() && \
    KEPT_RUBY_PACKAGES=() && \
    # Required for building multiple packages.
    # TEMP_PACKAGES+=(build-essential) && \
    TEMP_PACKAGES+=(pkg-config) && \
    # TEMP_PACKAGES+=(cmake) && \
    TEMP_PACKAGES+=(git) && \
    TEMP_PACKAGES+=(automake) && \
    TEMP_PACKAGES+=(autoconf) && \
    KEPT_PACKAGES+=(wget) && \
    # logging
    KEPT_PACKAGES+=(gawk) && \
    KEPT_PACKAGES+=(pv) && \
    # required for S6 overlay
    # curl kept for healthcheck
    # ca-certificates kept for python
    TEMP_PACKAGES+=(gnupg2) && \
    TEMP_PACKAGES+=(file) && \
    TEMP_PACKAGES+=(curl) && \
    KEPT_PACKAGES+=(ca-certificates) && \
    # a few KEPT_PACKAGES for debugging - they can be removed in the future
    KEPT_PACKAGES+=(procps nano aptitude netcat) && \
#
# define packages needed for NoiseCapt
    KEPT_PACKAGES+=(bc) && \
    KEPT_PACKAGES+=(lighttpd) && \
    KEPT_PACKAGES+=(iputils-ping) && \
    KEPT_PACKAGES+=(alsa-utils) && \
    KEPT_PIP_PACKAGES+=(tzlocal) && \
#
# Install all these packages:
    apt-get update && \
    apt-get install -o APT::Autoremove::RecommendsImportant=0 -o APT::Autoremove::SuggestsImportant=0 -o Dpkg::Options::="--force-confold" --force-yes -y --no-install-recommends  --no-install-suggests\
        ${KEPT_PACKAGES[@]} \
        ${TEMP_PACKAGES[@]} \
        && \
    git config --global advice.detachedHead false && \
    pip install ${KEPT_PIP_PACKAGES[@]} && \
    gem install twurl && \
#
# Install NoiseCapt (it was copied in at the top of the script, so this is
# mainly moving files to the correct location and creating symlinks):
    mkdir -p /usr/share/noisecapt/html && \
    mkdir -p /usr/share/noisecapt/stage && \
    mkdir -p /etc/services.d/noisecapt && \
    mkdir -p /run/noisecapt && \
    pushd /noisecapt && \
       cp scripts/* /usr/share/planefence && \
       cp services.d/start_noisecapt /etc/services.d/noisecapt/run && \
       cp img/favicon.ico /usr/share/noisecapt/html && \
       chmod a+x /usr/share/noisecapt/*.sh /etc/services.d/noisecapt/run && \
       popd && \
#
# Install the cleanup service that ensures that older log files and data get deleted after a user-defined period:
    mkdir -p /etc/services.d/cleanup && \
    cp /planefence/services.d/start_cleanup /etc/services.d/cleanup/run && \
    chmod a+x /etc/services.d/cleanup/run && \
#
# Configure lighttpd to start and work with planefence:
    # move the s6 service in place:
       mkdir -p /etc/services.d/lighttpd && \
       cp /planefence/services.d/start_lighttpd /etc/services.d/lighttpd/run && \
       chmod a+x /etc/services.d/lighttpd/run && \
    # Place and enable the lighty mod:
       cp /planefence/88-planefence.conf /etc/lighttpd/conf-available && \
       ln -sf /etc/lighttpd/conf-available/88-planefence.conf /etc/lighttpd/conf-enabled && \
#
# Do some other stuff
    [ -f "/planefence/bash_aliases" ] cat /planefence/bash_aliases >> /root/.bashrc && \
#
# install S6 Overlay
    curl -s https://raw.githubusercontent.com/mikenye/deploy-s6-overlay/master/deploy-s6-overlay.sh | sh && \
#
# Clean up
    apt-get remove -y ${TEMP_PACKAGES[@]} && \
    apt-get autoremove -o APT::Autoremove::RecommendsImportant=0 -o APT::Autoremove::SuggestsImportant=0 -y && \
    apt-get clean -y && \
    rm -rf /src/* /tmp/* /var/lib/apt/lists/* /etc/services.d/planefence/.blank /etc/services.d/socket30003/.blank /run/socket30003/install-* /.dockerenv
    # following lines commented out for development purposes
    # rm -rf /git/* /planefence/*

ENTRYPOINT [ "/init" ]

EXPOSE 80
EXPOSE 30003
