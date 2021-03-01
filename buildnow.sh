#!/bin/bash
#
set -x

# rebuild the container

pushd /etc/docker/build/docker-planefence

git pull
echo Building:
a=$(git log -n 1 --source | head -1) ; b=$(git log -n 1 --source | tail -1| sed 's/^\s*//'); echo ${a:7:7}-$b
time docker build --compress --pull "$@" -t kx1t/planefence .

pushd /opt/planefence
docker-compose up -d
popd
popd

echo Press control-c to stop seeing the logs...
docker logs -f planefence
