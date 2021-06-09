#!/bin/bash
#
set -x
set -e
trap 'echo -e "[ERROR] $0 in line $LINENO when executing: $BASH_COMMAND"' ERR

# rebuild the container
mv rootfs/usr/share/planefence/airlinecodes.txt /tmp
curl --compressed -s -L -o rootfs/usr/share/planefence/airlinecodes.txt https://raw.githubusercontent.com/kx1t/planefence-airlinecodes/main/airlinecodes.txt

# make the build certs root_certs folder:
# Note that this is normally done as part of the github actions - we don't have those here, so we need to do it ourselves before building:
#ls -la /etc/ssl/certs/
mkdir -p ./root_certs/etc/ssl/certs
mkdir -p ./root_certs/usr/share/ca-certificates/mozilla
cp --no-dereference /etc/ssl/certs/*.crt ./root_certs/etc/ssl/certs
cp --no-dereference /etc/ssl/certs/*.pem ./root_certs/etc/ssl/certs
cp --no-dereference /usr/share/ca-certificates/mozilla/*.crt ./root_certs/usr/share/ca-certificates/mozilla

echo "$(git branch --show-current)_($(git rev-parse --short HEAD))_$(date +%y-%m-%d-%T%Z)" > rootfs/usr/share/planefence/branch

docker build . -t planefence
mv /tmp/airlinecodes.txt rootfs/usr/share/planefence/
rm -f rootfs/usr/share/planefence/branch
rm -rf ./root_certs
