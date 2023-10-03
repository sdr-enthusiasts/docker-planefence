#!/bin/bash
# shellcheck disable=SC2086

[[ "$1" != "" ]] && BRANCH="$1" || BRANCH="$(git branch --show-current)"
[[ "$BRANCH" == "main" ]] && TAG="latest" || TAG="$BRANCH"
[[ "$ARCHS" == "" ]] && ARCHS="linux/armhf,linux/arm64,linux/amd64"

BASETARGET1=ghcr.io/sdr-enthusiasts
#BASETARGET2=kx1t

IMAGE1="$BASETARGET1/docker-planefence:$TAG"
#IMAGE2="$BASETARGET2/$(pwd | sed -n 's|.*/docker-\(.*\)|\1|p'):$TAG"


echo "press enter to start building $IMAGE1 from $BRANCH"

#shellcheck disable=SC2162
read

starttime="$(date +%s)"
# rebuild the container
set -x

git pull -a

docker buildx build -f Dockerfile --compress --push $2 --platform $ARCHS --tag "$IMAGE1" .
# [[ $? ]] && docker buildx build --compress --push $2 --platform $ARCHS --tag $IMAGE2 .

echo "Total build time: $(( $(date +%s) - starttime )) seconds"
