#!/bin/bash
#
set -x

[[ "$1" != "-" ]] && BRANCH="$1"
[[ "$BRANCH" == "-" ]] && BRANCH=dev

[[ "$BRANCH" == "main" ]] && TAG="latest" || TAG="$BRANCH"

PLATFORMS=linux/armhf,linux/arm64,linux/amd64,linux/386
#PLATFORMS=linux/armhf,linux/arm64

# rebuild the container
pushd ~/git/docker-planefence
git checkout $BRANCH || exit 2
git pull
mv rootfs/usr/share/planefence/airlinecodes.txt /tmp
curl --compressed -s -L -o rootfs/usr/share/planefence/airlinecodes.txt https://raw.githubusercontent.com/kx1t/planefence-airlinecodes/main/airlinecodes.txt

# make the build certs root_certs folder:
# Note that this is normally done as part of the github actions - we don't have those here, so we need to do it ourselves before building:
#ls -la /etc/ssl/certs/
#mkdir -p ./root_certs/etc/ssl/certs
#mkdir -p ./root_certs/usr/share/ca-certificates/mozilla

#cp -P /etc/ssl/certs/*.crt ./root_certs/etc/ssl/certs
#cp -P /etc/ssl/certs/*.pem ./root_certs/etc/ssl/certs
#cp -P /usr/share/ca-certificates/mozilla/*.crt ./root_certs/usr/share/ca-certificates/mozilla

echo "$(git branch --show-current)_($(git rev-parse --short HEAD))_$(date +%y-%m-%d-%T%Z)" > rootfs/usr/share/planefence/branch

DOCKER_BUILDKIT=1 docker buildx build --progress=plain --compress --push $2 --platform $PLATFORMS --tag kx1t/planefence:$TAG .
mv /tmp/airlinecodes.txt rootfs/usr/share/planefence/
rm -f rootfs/usr/share/planefence/branch
rm -rf ./root_certs
popd
