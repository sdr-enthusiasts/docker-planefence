FROM ghcr.io/sdr-enthusiasts/docker-baseimage:wreadsb

RUN set -xe && \
    # define packages needed for installation and general management of the container:
    TEMP_PACKAGES=() && \
    KEPT_PACKAGES=() && \
    KEPT_PIP3_PACKAGES=() && \
    KEPT_RUBY_PACKAGES=() && \
    #
    TEMP_PACKAGES+=(python3-pip) && \
    #
    KEPT_PACKAGES+=(unzip) && \
    KEPT_PACKAGES+=(psmisc) && \
    KEPT_PACKAGES+=(procps nano) && \
    KEPT_PACKAGES+=(python3) && \
    KEPT_PACKAGES+=(python3-paho-mqtt) && \
    KEPT_PACKAGES+=(jq) && \
    KEPT_PACKAGES+=(gnuplot-nox) && \
    KEPT_PACKAGES+=(lighttpd) && \
    KEPT_PACKAGES+=(perl) && \
    KEPT_PACKAGES+=(iputils-ping) && \
    KEPT_PACKAGES+=(php-cgi) && \
    KEPT_PACKAGES+=(html-xml-utils) && \
    KEPT_PACKAGES+=(file) && \
    KEPT_PACKAGES+=(jpegoptim) && \
    KEPT_PACKAGES+=(pngquant) && \
    #
    KEPT_PIP3_PACKAGES+=(tzlocal) && \
    KEPT_PIP3_PACKAGES+=(discord-webhook==1.0.0) && \
    #    KEPT_PIP3_PACKAGES+=(discord-webhook) && \
    KEPT_PIP3_PACKAGES+=(requests) && \
    KEPT_PIP3_PACKAGES+=(geopy) && \
    #
    # Install all the apt, pip3, and gem (ruby) packages:
    apt-get update -q && \
    apt-get install -q -o APT::Autoremove::RecommendsImportant=0 -o APT::Autoremove::SuggestsImportant=0 -o Dpkg::Options::="--force-confold" -y --no-install-recommends  --no-install-suggests ${TEMP_PACKAGES[@]} ${KEPT_PACKAGES[@]} && \
    pip3 install --break-system-packages --no-cache-dir ${KEPT_PIP3_PACKAGES[@]} && \
    #
    # Clean up
    echo Uninstalling $TEMP_PACKAGES && \
    apt-get remove -y -q ${TEMP_PACKAGES[@]} && \
    apt-get autoremove -q -o APT::Autoremove::RecommendsImportant=0 -o APT::Autoremove::SuggestsImportant=0 -y && \
    apt-get clean -y -q && \
    # remove pycache
    { find /usr | grep -E "/__pycache__$" | xargs rm -rf || true; } && \
    rm -rf \
    /src/* \
    /var/cache/* \
    /tmp/* \
    /var/lib/apt/lists/* \
    /.dockerenv \
    /git
#
COPY rootfs/ /
#
# COPY ATTRIBUTION.md /usr/share/planefence/stage/attribution.txt
#
RUN \
    --mount=type=bind,source=./,target=/app/ \
    set -xe \
    #
    #
    # Install Planefence (it was copied in with /rootfs, so this is
    # mainly moving files to the correct location and creating symlinks):
    chmod a+x /usr/share/planefence/*.sh /usr/share/planefence/*.py /usr/share/planefence/*.pl && \
    ln -s /usr/share/socket30003/socket30003.cfg /usr/share/planefence/socket30003.cfg && \
    ln -s /usr/share/planefence/config_tweeting.sh /root/config_tweeting.sh && \
    if curl --compressed --fail -sSL https://raw.githubusercontent.com/kx1t/planefence-airlinecodes/main/airlinecodes.txt > /tmp/airlinecodes.txt; then mv -f /tmp/airlinecodes.txt /usr/share/planefence/airlinecodes.txt; fi && \
    if curl --compressed --fail -sSL https://github.com/rikgale/VRSOperatorFlags/raw/main/Silhouettes.zip > /tmp/Silhouettes.zip; then mv -f /tmp/Silhouettes.zip /usr/share/planefence/stage/Silhouettes.zip; fi && \
    #
    # Ensure the planefence and plane-alert config is available for lighttpd:
    ln -sf /etc/lighttpd/conf-available/88-planefence.conf /etc/lighttpd/conf-enabled && \
    ln -sf /etc/lighttpd/conf-available/88-plane-alert.conf /etc/lighttpd/conf-enabled && \
    # Install dump1090.socket30003. Note - this could move to a lower layer, but we need to have rootfs copied in.
    # In any case, it doesn't take much (build)time.
    pushd /app/socket30003 && \
    ./install.pl -install /usr/share/socket30003 -data /run/socket30003 -log /run/socket30003 -output /run/socket30003 -pid /run/socket30003 && \
    chmod a+x /usr/share/socket30003/*.pl && \
    rm -rf /run/socket30003/install-* && \
    popd && \
    # Move the mqtt.py script to an executable directory
    mv -f /scripts/mqtt.py /usr/local/bin/mqtt && \
    #
    # version
    branch="##main##" && \
    echo "${branch//#/}_($(curl -ssL "https://api.github.com/repos/sdr-enthusiasts/docker-planefence/commits/main" |  awk '{if ($1=="\"sha\":") {print substr($2,2,7); exit}}'))_$(date +%y-%m-%d-%T%Z)" | tee /root/.buildtime && \
    cp -f /root/.buildtime /.VERSION && \
    # Do some other stuff
    echo "alias dir=\"ls -alsv\"" >> /root/.bashrc && \
    echo "alias nano=\"nano -l\"" >> /root/.bashrc

#
# No need for SHELL and ENTRYPOINT as those are inherited from the base image
#

EXPOSE 80
