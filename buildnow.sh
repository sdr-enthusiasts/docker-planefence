#!/bin/bash
#
set -x

# rebuild the container

cd /etc/docker/build/docker-planefence

git pull

time docker build --compress --pull -t kx1t/planefence .

pushd /opt/planefence
docker-compose up -d
popd

echo Press control-c to stop seeing the logs...
docker logs -f planefence
