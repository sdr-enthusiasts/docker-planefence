#!/bin/bash
#
set -x

BRANCH=dev
[[ "$1" != "" ]] && BRANCH="$1"
[[ "$BRANCH" == "main" ]] && TAG="latest" || TAG="$BRANCH"

# rebuild the container
pushd ~/docker-planefence
git checkout $BRANCH || exit 2

git pull
docker buildx build --compress --push --platform linux/armhf,linux/arm64 --tag kx1t/planefence:$TAG .
popd
