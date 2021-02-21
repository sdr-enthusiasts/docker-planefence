#!/bin/bash
# recover your persistent data
echo Recovering your data...
mkdir -p ${HOME}/.planefence
sudo cp -a /var/lib/docker/volumes/planefence_planefence/_data/{*,.twurlrc}  ${HOME}/.planefence
echo Restarting Planefence...
docker restart planefence
echo Done!
