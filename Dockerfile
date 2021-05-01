FROM debian:stable-slim

ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Copy needs to be here to prevent github actions from failing.
# SSL Certs are pre-loaded into the rootfs via a job in github action:
# See: "Copy CA Certificates from GitHub Runner to Image rootfs" in deploy.yml
COPY rootfs/ /

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
    # KEPT_PACKAGES+=(wget) && \
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
    KEPT_PACKAGES+=(netcat) && \
    KEPT_PACKAGES+=(unzip) && \
    # a few KEPT_PACKAGES for debugging - they can be removed in the future
    KEPT_PACKAGES+=(procps nano) && \
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
    # KEPT_PACKAGES+=(chromium) && \ # adds 400 Mb to image!
    # KEPT_PACKAGES+=(alsa-utils) && \
    KEPT_PIP_PACKAGES+=(tzlocal) && \
    KEPT_RUBY_PACKAGES+=(twurl) && \
    echo ${TEMP_PACKAGES[*]} > /tmp/vars.tmp && \
#
# Install all these packages:
    apt-get update && \
    apt-get install -o APT::Autoremove::RecommendsImportant=0 -o APT::Autoremove::SuggestsImportant=0 -o Dpkg::Options::="--force-confold" --force-yes -y --no-install-recommends  --no-install-suggests\
        ${KEPT_PACKAGES[@]} \
        ${TEMP_PACKAGES[@]} \
        && \
    git config --global advice.detachedHead false && \
    pip install ${KEPT_PIP_PACKAGES[@]} && \
    gem install twurl

# Copy the planefence and plane-alert program files in place:
COPY planefence/ /planefence
COPY plane-alert/ /plane-alert
COPY ATTRIBUTION.md /planefence

RUN set -x && \
#
# Install dump1090.socket30003:
    mkdir -p /usr/share/socket30003 && \
    mkdir -p /run/socket30003 && \
    mkdir -p /etc/services.d/socket30003 && \
    git clone --depth=1 https://github.com/kx1t/dump1090.socket30003.git /git/socket30003 && \
    pushd "/git/socket30003" && \
       ./install.pl -install /usr/share/socket30003 -data /run/socket30003 -log /run/socket30003 -output /run/socket30003 -pid /run/socket30003 && \
       cp /planefence/services.d/start_socket30003 /etc/services.d/socket30003/run && \
       chmod a+x /usr/share/socket30003/*.pl && \
       chmod a+x /etc/services.d/socket30003/run && \
    popd && \
#
# Remove the temporary files because we are done with them:
    rm -rf /etc/services.d/socket30003/.blank && \
    rm -rf /run/socket30003/install-* && \
    rm -rf /git/socket30003

RUN set -x && \
#
# Install Planefence (it was copied in at the top of the script, so this is
# mainly moving files to the correct location and creating symlinks):
    mkdir -p /usr/share/planefence/html/plane-alert && \
    mkdir -p /usr/share/planefence/stage && \
    mkdir -p /usr/share/planefence/persist && \
    mkdir -p /etc/services.d/planefence && \
    pushd /planefence && \
       cp scripts/* /usr/share/planefence && \
       cp jscript/* /usr/share/planefence/stage && \
       cp planefence.config /usr/share/planefence/stage && \
       cp planefence-ignore.txt /usr/share/planefence/stage && \
       cp ATTRIBUTION.md /usr/share/planefence/stage/attribution.txt && \
       cp services.d/start_planefence /etc/services.d/planefence/run && \
       chmod a+x /usr/share/planefence/*.sh /usr/share/planefence/*.py /usr/share/planefence/*.pl /etc/services.d/planefence/run && \
       ln -s /usr/share/socket30003/socket30003.cfg /usr/share/planefence/socket30003.cfg && \
       ln -s /usr/share/planefence/config_tweeting.sh /root/config_tweeting.sh && \
       curl -s -L -o scripts/airlinecodes.txt https://raw.githubusercontent.com/kx1t/planefence-airlinecodes/main/airlinecodes.txt && \
    popd && \
    git clone --depth=1 https://github.com/kx1t/docker-planefence /git/docker-planefence && \
    pushd /git/docker-planefence && \
       echo "main_($(git rev-parse --short HEAD))_$(date +%y-%m-%d-%T%Z)" > /root/.buildtime && \
       #echo $(date +"%Y-%m-%d %H:%M:%S %Z") \($(git show --oneline | head -1)\) > /root/.buildtime && \
       cp .img/background.jpg /usr/share/planefence/stage && \
    popd && \
    rm -rf /git/docker-planefence

RUN set -x && \
#
# Install the cleanup service that ensures that older log files and data get deleted after a user-defined period:
    mkdir -p /etc/services.d/cleanup && \
    cp /planefence/services.d/start_cleanup /etc/services.d/cleanup/run && \
    chmod a+x /etc/services.d/cleanup/run && \
#
# Install the get-pa--alertlist service that ensures that the Plane Alert alertlist is up to date:
    mkdir -p /etc/services.d/get-pa-alertlist && \
    cp /planefence/services.d/start_get-pa-alertlist /etc/services.d/get-pa-alertlist/run && \
    cp /planefence/services.d/get-pa-alertlist.sh /etc/services.d/get-pa-alertlist/get-pa-alertlist.sh && \
    chmod a+x /etc/services.d/get-pa-alertlist/* && \
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
# Remove /planefence because we're done with it
    rm -rf /planefence \
           /etc/services.d/planefence/.blank

RUN set -x && \
#
# Install Plane-Alert
    mkdir -p /usr/share/plane-alert/html && \
    cp -r /plane-alert/* /usr/share/plane-alert && \
    chmod a+x /usr/share/plane-alert/*.sh && \
    cp /plane-alert/88-plane-alert.conf /etc/lighttpd/conf-available && \
    ln -sf /etc/lighttpd/conf-available/88-plane-alert.conf /etc/lighttpd/conf-enabled && \
#
# Remove /plane-alert because we're done with it
    rm -rf /plane-alert

RUN set -x && \
#
# Do some other stuff
    echo "alias dir=\"ls -alsv\"" >> /root/.bashrc && \
    echo "alias nano=\"nano -l\"" >> /root/.bashrc && \
#
# install S6 Overlay
    curl -s https://raw.githubusercontent.com/mikenye/deploy-s6-overlay/master/deploy-s6-overlay.sh | sh && \
#
# Clean up
    TEMP_PACKAGES="$(</tmp/vars.tmp)" && \
    echo Uninstalling $TEMP_PACKAGES && \
    apt-get remove -y $TEMP_PACKAGES && \
    apt-get autoremove -o APT::Autoremove::RecommendsImportant=0 -o APT::Autoremove::SuggestsImportant=0 -y && \
    apt-get clean -y && \
    rm -rf \
	     /src/* \
	     /tmp/* \
	     /var/lib/apt/lists/* \
	     /.dockerenv \
	     /git


ENTRYPOINT [ "/init" ]

EXPOSE 80
