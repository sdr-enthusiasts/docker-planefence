FROM ghcr.io/sdr-enthusiasts/docker-baseimage:planefence_base
LABEL maintainer="Ramon F. Kolb kx1t / SDR-Enthusiasts"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY rootfs/ /

RUN \
    --mount=type=bind,source=./,target=/app/ \
    set -xe && \
    #
    # Install Planefence (it was copied in with /rootfs, so this is
    # mainly moving files to the correct location and creating symlinks):
    chmod a+x /usr/share/planefence/*.sh /usr/share/planefence/*.py /usr/share/planefence/*.pl /scripts/post2telegram.sh && \
    ln -s /usr/share/socket30003/socket30003.cfg /usr/share/planefence/socket30003.cfg && \
    # ln -s /usr/share/planefence/config_tweeting.sh /root/config_tweeting.sh && \
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

EXPOSE 80
