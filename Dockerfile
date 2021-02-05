FROM debian:stable-slim

ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2 
    
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

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
    #
    # Get prerequisite packages for PlaneFence:
    #
    KEPT_PACKAGES+=(python-pip python-numpy python-pandas python-dateutil jq bc gnuplot git sox) && \
    KEPT_PIP_PACKAGES+=(tzlocal) && \
    #
    # Install packages.
    #
    apt-get update && \
    apt-get install -o Dpkg::Options::="--force-confold" --force-yes -y --no-install-recommends \
        ${KEPT_PACKAGES[@]} \
        ${TEMP_PACKAGES[@]} \
        && \
    git config --global advice.detachedHead false && \
    #
    # Use normal shell commands to install
    #
    
    #
    # install S6 Overlay
    curl -s https://raw.githubusercontent.com/mikenye/deploy-s6-overlay/master/deploy-s6-overlay.sh | sh && \
    #
    # Clean up
    apt-get remove -y ${TEMP_PACKAGES[@]} && \
    apt-get autoremove -y && \
    rm -rf /git/* /src/* /tmp/* /var/lib/apt/lists/*

COPY rootfs/ /

ENTRYPOINT [ "/init" ]

EXPOSE 80

# Add healthcheck
HEALTHCHECK --start-period=3600s --interval=600s CMD /scripts/healthcheck.sh
