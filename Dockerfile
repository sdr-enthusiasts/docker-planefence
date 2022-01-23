FROM fredclausen/baseimage

ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# COPY root_certs/ /

RUN set -x && \
# define packages needed for installation and general management of the container:
    TEMP_PACKAGES=() && \
    KEPT_PACKAGES=() && \
    KEPT_PIP_PACKAGES=() && \
    KEPT_PIP3_PACKAGES=() && \
    KEPT_RUBY_PACKAGES=() && \
    # Required for building multiple packages.
    TEMP_PACKAGES+=(pkg-config) && \
    TEMP_PACKAGES+=(git) && \
#    TEMP_PACKAGES+=(automake) && \
#    TEMP_PACKAGES+=(autoconf) && \
    # logging
#    KEPT_PACKAGES+=(gawk) && \
#    KEPT_PACKAGES+=(pv) && \
    # required for S6 overlay
    # curl kept for healthcheck
    # ca-certificates kept for python
#    TEMP_PACKAGES+=(gnupg2) && \
#    TEMP_PACKAGES+=(file) && \
#    KEPT_PACKAGES+=(curl) && \
#    KEPT_PACKAGES+=(ca-certificates) && \
    KEPT_PACKAGES+=(netcat) && \
    KEPT_PACKAGES+=(unzip) && \
    KEPT_PACKAGES+=(psmisc) && \
    # a few KEPT_PACKAGES for debugging - they can be removed in the future
    KEPT_PACKAGES+=(procps nano) && \
    # Needed to pip3 install discord for some archs \
    TEMP_PACKAGES+=(gcc) && \
    TEMP_PACKAGES+=(python3-dev) && \
#
# define packages needed for PlaneFence, including socket30003
#    KEPT_PACKAGES+=(python-pip) && \
    KEPT_PACKAGES+=(python3-numpy) && \
    KEPT_PACKAGES+=(python3-pandas) && \
    KEPT_PACKAGES+=(python3-dateutil) && \
    KEPT_PACKAGES+=(jq) && \
    KEPT_PACKAGES+=(bc) && \
    KEPT_PACKAGES+=(gnuplot-nox) && \
    KEPT_PACKAGES+=(lighttpd) && \
    KEPT_PACKAGES+=(perl) && \
    KEPT_PACKAGES+=(iputils-ping) && \
    KEPT_PACKAGES+=(ruby) && \
    KEPT_PACKAGES+=(php-cgi) && \
    KEPT_PACKAGES+=(python3) && \
    KEPT_PACKAGES+=(python3-pip) && \
    KEPT_PIP_PACKAGES+=(tzlocal) && \
    KEPT_PIP3_PACKAGES+=(discord) && \
    KEPT_PIP3_PACKAGES+=(requests) && \
    KEPT_RUBY_PACKAGES+=(twurl) && \
    echo ${TEMP_PACKAGES[*]} > /tmp/vars.tmp && \
    # We need some of the temp packages for building python3 dependencies so save those for the next layer
    echo ${KEPT_PIP3_PACKAGES[*]} > /tmp/pip3.tmp && \
#
# Install all the KEPT packages (+ pkgconfig):
    apt-get update && \
    apt-get install -o APT::Autoremove::RecommendsImportant=0 -o APT::Autoremove::SuggestsImportant=0 -o Dpkg::Options::="--force-confold" -y --no-install-recommends  --no-install-suggests\
        pkg-config ${KEPT_PACKAGES[@]}&& \
    pip install ${KEPT_PIP_PACKAGES[@]} && \
    gem install twurl
#
# Copy needs to be here to prevent github actions from failing.
# SSL Certs are pre-loaded into the rootfs via a job in github action:
# See: "Copy CA Certificates from GitHub Runner to Image rootfs" in deploy.yml
COPY rootfs/ /
#
# Copy the planefence and plane-alert program files in place:
COPY ATTRIBUTION.md /usr/share/planefence/stage/attribution.txt
#
RUN set -x && \
#
# First install the TEMP_PACKAGES. We do this here, so we can delete them again from the layer once installation is complete
    TEMP_PACKAGES="$(</tmp/vars.tmp)" && \
    KEPT_PIP3_PACKAGES="$(</tmp/pip3.tmp)" && \
    apt-get install -o APT::Autoremove::RecommendsImportant=0 -o APT::Autoremove::SuggestsImportant=0 -o Dpkg::Options::="--force-confold" -y --no-install-recommends  --no-install-suggests ${TEMP_PACKAGES[@]} && \
pip3 install ${KEPT_PIP3_PACKAGES[@]} && \
git config --global advice.detachedHead false && \
# Install dump1090.socket30003:
    pushd /src/socket30003 && \
       ./install.pl -install /usr/share/socket30003 -data /run/socket30003 -log /run/socket30003 -output /run/socket30003 -pid /run/socket30003 && \
       chmod a+x /usr/share/socket30003/*.pl && \
   popd && \
#
# Remove the temporary files because we are done with them:
    rm -rf /run/socket30003/install-* && \
#
# Install Planefence (it was copied in at the top of the script, so this is
# mainly moving files to the correct location and creating symlinks):
    chmod a+x /usr/share/planefence/*.sh /usr/share/planefence/*.py /usr/share/planefence/*.pl /etc/services.d/planefence/run && \
    ln -s /usr/share/socket30003/socket30003.cfg /usr/share/planefence/socket30003.cfg && \
    ln -s /usr/share/planefence/config_tweeting.sh /root/config_tweeting.sh && \
    curl --compressed -s -L -o /usr/share/planefence/airlinecodes.txt https://raw.githubusercontent.com/kx1t/planefence-airlinecodes/main/airlinecodes.txt && \
    curl --compressed -s -L -o /usr/share/planefence/stage/Silhouettes.zip https://github.com/rikgale/VRSOperatorFlags/raw/main/Silhouettes.zip && \
    echo "main_($(git ls-remote https://github.com/kx1t/docker-planefence HEAD | awk '{ print substr($1,1,7)}'))_$(date +%y-%m-%d-%T%Z)" > /root/.buildtime && \
#
# Ensure the planefence and plane-alert config is available for lighttpd:
    ln -sf /etc/lighttpd/conf-available/88-planefence.conf /etc/lighttpd/conf-enabled && \
    ln -sf /etc/lighttpd/conf-available/88-plane-alert.conf /etc/lighttpd/conf-enabled && \
#
# Do some other stuff
    echo "alias dir=\"ls -alsv\"" >> /root/.bashrc && \
    echo "alias nano=\"nano -l\"" >> /root/.bashrc && \
#
# install S6 Overlay
#    curl --compressed -s https://raw.githubusercontent.com/mikenye/deploy-s6-overlay/master/deploy-s6-overlay.sh | sh && \
#
# Clean up
    TEMP_PACKAGES="$(</tmp/vars.tmp)" && \
    echo Uninstalling $TEMP_PACKAGES && \
    apt-get remove -y $TEMP_PACKAGES && \
    apt-get autoremove -o APT::Autoremove::RecommendsImportant=0 -o APT::Autoremove::SuggestsImportant=0 -y && \
    apt-get clean -y && \
    rm -rf \
#	     /src/* \
	     /tmp/* \
	     /var/lib/apt/lists/* \
	     /.dockerenv \
	     /git

ENTRYPOINT [ "/init" ]

EXPOSE 80
