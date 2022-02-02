FROM ghcr.io/fredclausen/docker-baseimage:python

ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN set -x && \
# define packages needed for installation and general management of the container:
    TEMP_PACKAGES=() && \
    KEPT_PACKAGES=() && \
    KEPT_PIP3_PACKAGES=() && \
    KEPT_RUBY_PACKAGES=() && \
#
    TEMP_PACKAGES+=(pkg-config) && \
    TEMP_PACKAGES+=(git) && \
    TEMP_PACKAGES+=(gcc) && \
    TEMP_PACKAGES+=(python3-dev) && \
    TEMP_PACKAGES+=(pkg-config) && \
#
    KEPT_PACKAGES+=(unzip) && \
    KEPT_PACKAGES+=(psmisc) && \
    KEPT_PACKAGES+=(procps nano) && \
    KEPT_PACKAGES+=(python3-numpy) && \
    KEPT_PACKAGES+=(python3-pandas) && \
    KEPT_PACKAGES+=(python3-dateutil) && \
    KEPT_PACKAGES+=(jq) && \
    KEPT_PACKAGES+=(gnuplot-nox) && \
    KEPT_PACKAGES+=(lighttpd) && \
    KEPT_PACKAGES+=(perl) && \
    KEPT_PACKAGES+=(iputils-ping) && \
    KEPT_PACKAGES+=(ruby) && \
    KEPT_PACKAGES+=(php-cgi) && \
#
    KEPT_PIP3_PACKAGES+=(tzlocal) && \
    KEPT_PIP3_PACKAGES+=(discord-webhook) && \
    KEPT_PIP3_PACKAGES+=(requests) && \
    KEPT_PIP3_PACKAGES+=(geopy) && \
#
    KEPT_RUBY_PACKAGES+=(twurl) && \
#
# Install all the apt, pip3, and gem (ruby) packages:
    apt-get update -q && \
    apt-get install -q -o APT::Autoremove::RecommendsImportant=0 -o APT::Autoremove::SuggestsImportant=0 -o Dpkg::Options::="--force-confold" -y --no-install-recommends  --no-install-suggests ${TEMP_PACKAGES[@]} ${KEPT_PACKAGES[@]} && \
    gem install twurl && \
    pip3 install ${KEPT_PIP3_PACKAGES[@]} && \
#
# Do this here while we still have git installed:
    git config --global advice.detachedHead false && \
    echo "main_($(git ls-remote https://github.com/kx1t/docker-planefence HEAD | awk '{ print substr($1,1,7)}'))_$(date +%y-%m-%d-%T%Z)" > /root/.buildtime && \
# Clean up
    echo Uninstalling $TEMP_PACKAGES && \
    apt-get remove -y -q ${TEMP_PACKAGES[@]} && \
    apt-get autoremove -q -o APT::Autoremove::RecommendsImportant=0 -o APT::Autoremove::SuggestsImportant=0 -y && \
    apt-get clean -y -q && \
    rm -rf \
      /src/* \
      /tmp/* \
      /var/lib/apt/lists/* \
      /.dockerenv \
      /git
#
COPY rootfs/ /
#
COPY ATTRIBUTION.md /usr/share/planefence/stage/attribution.txt
#
RUN set -x && \
#
#
# Install Planefence (it was copied in with /rootfs, so this is
# mainly moving files to the correct location and creating symlinks):
    chmod a+x /usr/share/planefence/*.sh /usr/share/planefence/*.py /usr/share/planefence/*.pl /etc/services.d/planefence/run && \
    ln -s /usr/share/socket30003/socket30003.cfg /usr/share/planefence/socket30003.cfg && \
    ln -s /usr/share/planefence/config_tweeting.sh /root/config_tweeting.sh && \
    curl --compressed -s -L -o /usr/share/planefence/airlinecodes.txt https://raw.githubusercontent.com/kx1t/planefence-airlinecodes/main/airlinecodes.txt && \
    curl --compressed -s -L -o /usr/share/planefence/stage/Silhouettes.zip https://github.com/rikgale/VRSOperatorFlags/raw/main/Silhouettes.zip && \
#
# Ensure the planefence and plane-alert config is available for lighttpd:
    ln -sf /etc/lighttpd/conf-available/88-planefence.conf /etc/lighttpd/conf-enabled && \
    ln -sf /etc/lighttpd/conf-available/88-plane-alert.conf /etc/lighttpd/conf-enabled && \
# Install dump1090.socket30003. Note - this could move to a lower layer, but we need to have rootfs copied in.
# In any case, it doesn't take much (build)time.
    pushd /src/socket30003 && \
       ./install.pl -install /usr/share/socket30003 -data /run/socket30003 -log /run/socket30003 -output /run/socket30003 -pid /run/socket30003 && \
       chmod a+x /usr/share/socket30003/*.pl && \
       rm -rf /run/socket30003/install-* && \
    popd && \
#
# Do some other stuff
    echo "alias dir=\"ls -alsv\"" >> /root/.bashrc && \
    echo "alias nano=\"nano -l\"" >> /root/.bashrc
#
ENTRYPOINT [ "/init" ]
#
EXPOSE 80
