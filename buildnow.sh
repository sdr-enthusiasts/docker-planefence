#!/bin/bash
# shellcheck disable=SC2086

[[ "$1" != "" ]] && BRANCH="$1" || BRANCH="$(git branch --show-current)"
[[ "$BRANCH" == "main" ]] && TAG="latest" || TAG="$BRANCH"
# [[ "$ARCHS" == "" ]] && ARCHS="linux/armhf,linux/arm64,linux/amd64"
[[ "$ARCHS" == "" ]] && ARCHS="linux/arm64,linux/amd64"

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
a="$(mktemp)"
cp -f Dockerfile "$a"
if grep -qi "darwin" <<< "$(uname -a)"; then
  sed -i '' "s/##main##/$BRANCH/g" Dockerfile
else
  sed -i "s/##main##/$BRANCH/g" Dockerfile
fi
docker buildx build -f Dockerfile --compress --push $2 --platform $ARCHS --tag "$IMAGE1" .
# [[ $? ]] && docker buildx build --compress --push $2 --platform $ARCHS --tag $IMAGE2 .
mv -f "$a" Dockerfile
echo "Total build time: $(( $(date +%s) - starttime )) seconds"
