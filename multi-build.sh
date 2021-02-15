#!/bin/bash
#
# Multi Build Scipt for manually building armhf and arm64 builds of the kx1t/planefence container
# As per https://www.docker.com/blog/multi-platform-docker-builds
#
# For this to work, add "experimental": "enabled" to ~/.docker/config.json
#

docker buildx use mybuilder
docker buildx inspect --bootstrap
#remove amd64 for now
#docker buildx build --platform linux/amd64,linux/arm/v6,linux/arm64,linux/arm/v7 -t kx1t/planefence:latest --push .
docker buildx build --platform linux/arm/v6,linux/arm64,linux/arm/v7 -t kx1t/planefence:latest --push .
