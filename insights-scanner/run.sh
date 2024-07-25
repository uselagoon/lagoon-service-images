#!/bin/bash

DOCKER_HOST="${DOCKER_HOST:-docker-host.lagoon.svc}"

# Read the comma-separated values
IFS=','

# Iterate over each image in the list
for image in $INSIGHT_SCAN_IMAGES; do
    # Populate the variable IMAGE_FULL for each iteration
    # IMAGE_FULL="$image"
    IMAGE_NAME=$(echo "$image" | awk -F'/' '{print $NF}' | cut -d':' -f1 | cut -d'@' -f1)
    IMAGE_FULL="$(echo "$image" | cut -d':' -f1 | cut -d'@' -f1):latest"
    
    echo "Processing image: $IMAGE_FULL"
    echo "With image name: $IMAGE_NAME"    
    . /app/insights-scan.sh
done
