#!/bin/bash
#
# Multi Build Scipt for manually building armhf and arm64 builds of the kx1t/planefence container
# As per https://www.docker.com/blog/multi-platform-docker-builds
#
# For this to work, add "experimental": "enabled" to ~/.docker/config.json
#

docker buildx build --platform linux/arm64 --compress --pull --no-cache -t kx1t/planefence:arm64 .
docker push kx1t/planefence:arm64
docker buildx build --platform linux/arm/v7 --compress --pull --no-cache -t kx1t/planefence:armv7 .
docker push kx1t/planefence:armv7
docker buildx build --platform linux/arm/v6 --compress --pull --no-cache -t kx1t/planefence:armv6 .
docker push kx1t/planefence:armv6

docker manifest create kx1t/planefence:latest kx1t/planefence:arm64 kx1t/planefence:armv7 kx1t/planefence:armv6
docker manifest push kx1t/planefence:latest
