
FROM debian:stable-slim

ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Copy needs to be here to prevent github actions from failing.
# SSL Certs are pre-loaded into the rootfs via a job in github action:
# See: "Copy CA Certificates from GitHub Runner to Image rootfs" in deploy.yml
COPY rootfs/ /

# Copy the planefence program files in place:
COPY planefence/ /planefence

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
    KEPT_PACKAGES+=(curl) && \
    KEPT_PACKAGES+=(ca-certificates) && \
    # a few KEPT_PACKAGES for debugging - they can be removed in the future
    KEPT_PACKAGES+=(procps nano aptitude netcat) && \
#
# define packages needed for PlaneFence, including socket30003
    KEPT_PACKAGES+=(python-pip) && \
    KEPT_PACKAGES+=(python-numpy) && \
    KEPT_PACKAGES+=(python-pandas) && \
    KEPT_PACKAGES+=(python-dateutil) && \
    KEPT_PACKAGES+=(jq) && \
    KEPT_PACKAGES+=(bc) && \
    KEPT_PACKAGES+=(gnuplot-nox) && \
    KEPT_PACKAGES+=(lighttpd) && \
    KEPT_PACKAGES+=(perl) && \
    KEPT_PACKAGES+=(iputils-ping) && \
    KEPT_PACKAGES+=(ruby) && \
    KEPT_PACKAGES+=(alsa-utils) && \
    KEPT_PIP_PACKAGES+=(tzlocal) && \
    KEPT_RUBY_PACKAGES+=(twurl) && \
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
# Install dump1090.socket30003:
    mkdir -p /usr/share/socket30003 && \
    mkdir -p /run/socket30003 && \
    mkdir -p /etc/services.d/socket30003 && \
    git clone https://github.com/kx1t/dump1090.socket30003.git /git/socket30003 && \
    pushd "/git/socket30003" && \
       ./install.pl -install /usr/share/socket30003 -data /run/socket30003 -log /run/socket30003 -output /run/socket30003 -pid /run/socket30003 && \
       cp /planefence/systemd/start_socket30003 /etc/services.d/socket30003/run && \
       chmod a+x /usr/share/socket30003/*.pl && \
       chmod a+x /etc/services.d/socket30003/run && \
    popd && \
#
# Install Planefence (it was copied in at the top of the script, so this is
# mainly moving files to the correct location and creating symlinks):
    mkdir -p /usr/share/planefence/html && \
    mkdir -p /usr/share/planefence/stage && \
    mkdir -p /etc/services.d/planefence && \
    pushd /planefence && \
       cp scripts/* /usr/share/planefence && \
       cp jscript/* /usr/share/planefence/stage && \
       cp systemd/start_planefence /etc/services.d/planefence/run && \
       chmod a+x /usr/share/planefence/*.sh /usr/share/planefence/*.py /usr/share/planefence/*.pl /etc/services.d/planefence/run && \
       ln -s /usr/share/socket30003/socket30003.cfg /usr/share/planefence/socket30003.cfg && \
       ln -s /usr/share/planefence/config_tweeting.sh /root/config_tweeting.sh && \
    popd && \
#
# Configure lighttpd to start and work with planefence:
    # move the s6 service in place:
       mkdir -p /etc/services.d/lighttpd && \
       cp /planefence/systemd/start_lighttpd /etc/services.d/lighttpd/run && \
       chmod a+x /etc/services.d/lighttpd/run && \
    # Place and enable the lighty mod:
       cp /planefence/88-planefence.conf /etc/lighttpd/conf-available && \
       ln -sf /etc/lighttpd/conf-available/88-planefence.conf /etc/lighttpd/conf-enabled && \
#
# install S6 Overlay
    curl -s https://raw.githubusercontent.com/mikenye/deploy-s6-overlay/master/deploy-s6-overlay.sh | sh && \
#
# Clean up
    apt-get remove -y ${TEMP_PACKAGES[@]} && \
    apt-get autoremove -o APT::Autoremove::RecommendsImportant=0 -o APT::Autoremove::SuggestsImportant=0 -y && \
    apt-get clean -y && \
    rm -rf /src/* /tmp/* /var/lib/apt/lists/* /etc/services.d/planefence/.blank /etc/services.d/socket30003/.blank /run/socket30003/install-*
    # following lines commented out for development purposes
    # rm -rf /git/* /planefence/*

ENTRYPOINT [ "/init" ]

EXPOSE 80
EXPOSE 30003
