#!/bin/bash
set -e

# try connect to docker-host 10 times before giving up
DOCKER_HOST_COUNTER=1
DOCKER_HOST_TIMEOUT=10
until docker -H ${DOCKER_HOST} info &> /dev/null
do
if [ $DOCKER_HOST_COUNTER -lt $DOCKER_HOST_TIMEOUT ]; then
    let DOCKER_HOST_COUNTER=DOCKER_HOST_COUNTER+1
    echo "${DOCKER_HOST} not available yet, waiting for 5 secs"
    sleep 5
else
    echo "could not connect to ${DOCKER_HOST}"
    exit 1
fi
done
