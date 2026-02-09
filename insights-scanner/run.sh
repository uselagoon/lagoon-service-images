#!/bin/bash

DOCKER_HOST="${DOCKER_HOST:-docker-host.lagoon.svc}"

# featureFlag searches for feature flag variables in the following locations
# and order:
#
# 1. The cluster-force feature flag, prefixed with LAGOON_FEATURE_FLAG_FORCE_,
#    as a scan pod environment variable. This is set via a flag on the
#    build-deploy controller. This overrides the other variables and allows
#    policy enforcement at the cluster level.
#
# 2. The regular feature flag, prefixed with LAGOON_FEATURE_FLAG_, in a
#    Lagoon build scoped env-var. This allows policy control at the project
#    level.
#
# 3. The cluster-default feature flag, prefixed with
#    LAGOON_FEATURE_FLAG_DEFAULT_, as a scan pod environment variable. This is
#    set via a flag on the build-deploy controller. This allows default policy
#    to be set at the cluster level, but maintains the ability to selectively
#    override at the project level.
#
# The value of the first variable found is printed to stdout. If the variable
# is not found, print an empty string. Additional arguments are ignored.
function featureFlag() {
	# check for argument
	[ "$1" ] || return

	local forceFlagVar defaultFlagVar flagVar

	# check build pod environment for the force policy first
	forceFlagVar="LAGOON_FEATURE_FLAG_FORCE_$1"
	[ "${!forceFlagVar}" ] && echo "${!forceFlagVar}" && return

	flagValue=$(buildEnvVarCheck "LAGOON_FEATURE_FLAG_$1")
	[ "$flagValue" ] && echo "$flagValue" && return

	# fall back to the default, if set.
	defaultFlagVar="LAGOON_FEATURE_FLAG_DEFAULT_$1"
	echo "${!defaultFlagVar}"
}

# Checks for a build scoped env var from Lagoon API.
function buildEnvVarCheck() {
  # check for argument
  [ "$1" ] || return

  local flagVar

  flagVar="$1"
  # check Lagoon environment variables
  flagValue=$(jq -r '.[] | select(.scope == "build" or .scope == "global") | select(.name == "'"$flagVar"'") | .value' <<< "$LAGOON_ENVIRONMENT_VARIABLES")
  [ "$flagValue" ] && echo "$flagValue" && return

  echo "$2"
}

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
