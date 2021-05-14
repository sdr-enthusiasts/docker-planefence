#!/bin/bash
#
set -x

[[ "$1" != "-" ]] && BRANCH="$1"
[[ "$BRANCH" == "-" ]] && BRANCH=dev

[[ "$BRANCH" == "main" ]] && TAG="latest" || TAG="$BRANCH"

# rebuild the container
pushd ~/git/docker-planefence
git checkout $BRANCH || exit 2
git pull
mv rootfs/usr/share/planefence/airlinecodes.txt /tmp
curl -s -L -o rootfs/usr/share/planefence/airlinecodes.txt https://raw.githubusercontent.com/kx1t/planefence-airlinecodes/main/airlinecodes.txt

# make the build certs root_certs folder:
# Note that this is normally done as part of the github actions - we don't have those here, so we need to do it ourselves before building:
#ls -la /etc/ssl/certs/
mkdir -p ./root_certs/etc/ssl/certs
mkdir -p ./root_certs/usr/share/ca-certificates/mozilla
cp --no-dereference /etc/ssl/certs/*.crt ./root_certs/etc/ssl/certs
cp --no-dereference /etc/ssl/certs/*.pem ./root_certs/etc/ssl/certs
cp --no-dereference /usr/share/ca-certificates/mozilla/*.crt ./root_certs/usr/share/ca-certificates/mozilla

export DOCKER_BUILDKIT=1

echo "$(git branch --show-current)_($(git rev-parse --short HEAD))_$(date +%y-%m-%d-%T%Z)" > rootfs/usr/share/planefence/branch

docker buildx build --compress --push $2 --platform linux/armhf,linux/arm64 --tag kx1t/planefence:$TAG .
mv /tmp/airlinecodes.txt rootfs/usr/share/planefence/
rm -f rootfs/usr/share/planefence/branch
rm -rf ./root_certs
popd
