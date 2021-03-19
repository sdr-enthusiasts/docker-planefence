#!/bin/bash
#
set -x

[[ "$1" != "-" ]] && BRANCH="$1"
[[ "$BRANCH" == "-" ]] && BRANCH=dev

[[ "$BRANCH" == "main" ]] && TAG="latest" || TAG="$BRANCH"

# rebuild the container
pushd ~/docker-planefence
git checkout $BRANCH || exit 2

git pull
mv planefence/scripts/airlinecodes.txt /tmp
curl -s -L -o planefence/scripts/airlinecodes.txt https://raw.githubusercontent.com/kx1t/planefence-airlinecodes/main/airlinecodes.txt
docker buildx build --compress --push $2 --platform linux/armhf,linux/arm64 --tag kx1t/planefence:$TAG .
mv /tmp/airlinecodes.txt planefence/scripts/
popd
