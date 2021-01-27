# docker-skeleton

In the Dockerfile use the following to get started:

* Uncommend ENV if you need to set any env variables. Format is like this:

```shell
ENV BRANCH_RTLSDR="ed0317e6a58c098874ac58b769cf2e609c18d9a5" \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    FEED="" \
    STATION_ID_ACARS="" \
    STATION_ID_VDLM="" \
    SERIAL_ACARS="" \
    SERIAL_VDLM="" \
    FREQS_ACARS="" \
    FREQS_VDLM="" \
    ENABLE_ACARS="" \
    ENABLE_VDLM="" \
    GAIN_ACARS="-10" \
    GAIN_VDLM="280" \
    ENABLE_WEB="true" \
    QUIET_LOGS="" \
    DB_SAVEALL="true"
```

* Under the run section is where you install packages and set up the system. Follow the format for adding debian packges to the list. `KEPT_PACKAGES` are packages you want installed for the system to run. `TEMP_PACKAGES` are uninstalled after the container is built. They're often needed for compiling stuff. The packages I left in there should be a good start to get S6-Overlay running (which you want) and have a few useful commands in the container.

* For any files you want to exist in the container (say your custom scripts and such) you add those in to the `rootfs` directory. That folder is copied in to the container and follows the Unix file system structure

* in `rootfs/etc/cont-init.d` you can put scripts that will run on container start. This is useful for sanity checking, say to make sure the required ENV variables are set or any required config files are presented/formatted right.

* in `rootfs/etc/service.d` is how you launch programs as services in the container. There is no `systemd` or anything running, so S6 takes care of that for us. Create sub folders for each service, in that folder create a file named `run` with the commands to start the service.

```shell
#!/usr/bin/with-contenv bash
#shellcheck shell=bash
# shellcheck disable=SC2016
if [ -n "$WEB" ]; then
  stdbuf -o0 gunicorn3 \
      -b "0.0.0.0:80" \
      -w 1 \
      --no-sendfile \
      -k eventlet \
      application:app \
    2>&1 | stdbuf -o0 sed --unbuffered '/^$/d' | stdbuf -o0 awk '{print "[webapp] " strftime("%Y/%m/%d %H:%M:%S", systime()) " " $0}'
else
  # web server must be disabled. Go to sleep forever
  sleep 86400
fi
```

To give an idea of the formatting

To build (in the directory with the dockerfile)

```shell
docker build -f Dockerfile "${REPO}/${IMAGE}:latest" --compress --push --platform "${PLATFORMS}" .
```

Replace (or set) the ENV variables for repo to be your dockerhub name, image to be the name for the image, and platforms you want to build for. Most likely `linux/arm/v7` or `linux/arm64`

To push, log in to docker on the command line and then

```shell
docker push repo/image
```
