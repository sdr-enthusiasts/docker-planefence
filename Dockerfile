FROM debian:stable-slim

ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY rootfs/ /

RUN set -x && \
    TEMP_PACKAGES=() && \
    KEPT_PACKAGES=() && \
    KEPT_PIP_PACKAGES=() && \
    # Required for building multiple packages.
    TEMP_PACKAGES+=(build-essential) && \
    TEMP_PACKAGES+=(pkg-config) && \
    TEMP_PACKAGES+=(cmake) && \
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
    KEPT_PACKAGES+=(procps) && \
    #
    # Get prerequisite packages for PlaneFence:
    #
    KEPT_PACKAGES+=(python-pip python-numpy python-pandas python-dateutil jq bc gnuplot-nox lighttpd perl) && \
    KEPT_PIP_PACKAGES+=(tzlocal) && \
    #
    # Install packages.
    #
    apt-get update && \
    apt-get install -o APT::Autoremove::RecommendsImportant=0 -o APT::Autoremove::SuggestsImportant=0 -o Dpkg::Options::="--force-confold" --force-yes -y --no-install-recommends  --no-install-suggests\
        ${KEPT_PACKAGES[@]} \
        ${TEMP_PACKAGES[@]} \
        && \
    git config --global advice.detachedHead false && \
    pip install ${KEPT_PIP_PACKAGES[@]} && \
    #
    # Use normal shell commands to install
    #
    # Install dump1090.socket30003
    mkdir -p /usr/share/socket30003 && \
    mkdir -p /run/socket30003 && \
    git clone https://github.com/kx1t/dump1090.socket30003.git /git/socket30003 && \
    pushd "/git/socket30003" && \
    ./install.pl -install /usr/share/socket30003 -data /run/socket30003 -log /run/socket30003 -output /run/socket30003 -pid /run/socket30003 && \
    popd && \
    #
    # Install PlaneFence
    mkdir -p /usr/share/planefence/html && \
    git clone https://github.com/kx1t/planefence4docker.git /git/planefence && \
    pushd /git/planefence && \
    cp scripts/* /usr/share/planefence && \
    cp jscript/* /usr/share/planefence/html && \
    cp systemd/start_* /usr/share/planefence && \
    cp systemd/start_planefence /etc/services.d/planefence/run && \
    cp systemd/start_socket30003 /etc/services.d/socket30003/run && \
    chmod a+x /usr/share/planefence/*.sh /usr/share/planefence/*.py /usr/share/planefence/*.pl /etc/services.d/planefence/run /etc/services.d/socket30003/run && \
    popd && \
    #
    # install S6 Overlay
    curl -s https://raw.githubusercontent.com/mikenye/deploy-s6-overlay/master/deploy-s6-overlay.sh | sh && \
    #
    # Clean up
    apt-get remove -y ${TEMP_PACKAGES[@]} && \
    apt-get autoremove -o APT::Autoremove::RecommendsImportant=0 -o APT::Autoremove::SuggestsImportant=0 -y && \
    apt-get clean -y && \
    rm -rf /git/* /src/* /tmp/* /var/lib/apt/lists/* /etc/services.d/planefence/.blank /etc/services.d/socket30003/.blank

ENTRYPOINT [ "/init" ]

EXPOSE 80
EXPOSE 30003

# Add healthcheck
HEALTHCHECK --start-period=3600s --interval=600s CMD /scripts/healthcheck.sh
