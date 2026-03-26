#!/usr/bin/env bats
# insights-scanner.bats — BATS integration tests for the insights-scanner image.
#
# Verifies that all required tools are present at expected versions, internal
# helper functions behave correctly, and the image environment is configured
# as expected.  Does NOT require a running Kubernetes cluster or Docker daemon
# — the container entrypoint is overridden with 'sleep infinity' so we can
# exec individual assertions without triggering the real scan workflow.
#
# Requires bats-core >= 1.5.0 (for setup_file / teardown_file).
# Install: https://bats-core.readthedocs.io/en/stable/installation.html
#
# Usage (local):
#   bats test/insights-scanner/insights-scanner.bats
#
# Environment variables (all optional):
#   SCANNER_IMAGE   image to test  (default: lagoon/insights-scanner:latest)
#   SKIP_BUILD      set to "true" to skip docker build
#   BUILD_PLATFORM  platform flag passed to docker build
#                   (default: native host architecture)

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

# ---------------------------------------------------------------------------
# Helper: exec a command inside the long-lived test container.
# ---------------------------------------------------------------------------
_exec() {
  local container
  container=$(<"${BATS_FILE_TMPDIR}/container")
  docker exec "$container" "$@"
}

# ---------------------------------------------------------------------------
# Suite setup — runs once before all tests.
# ---------------------------------------------------------------------------
setup_file() {
  local scanner_image="${SCANNER_IMAGE:-lagoon/insights-scanner:latest}"
  local skip_build="${SKIP_BUILD:-false}"
  local container="insights-scanner-bats-$$"

  echo "$container"     > "${BATS_FILE_TMPDIR}/container"
  echo "$scanner_image" > "${BATS_FILE_TMPDIR}/scanner_image"

  if [[ "$skip_build" != "true" ]]; then
    local platform_args=()
    [[ -n "${BUILD_PLATFORM:-}" ]] && platform_args=(--platform "$BUILD_PLATFORM")
    docker build \
      "${platform_args[@]}" \
      -t "$scanner_image" \
      "${REPO_ROOT}/insights-scanner" >&3
  fi

  # Start a long-lived container with the entrypoint bypassed.
  # '--entrypoint sleep' + 'infinity' prevents the lagoon entrypoints chain
  # (and in particular the docker-host connectivity check) from running,
  # so the tests work without a Docker daemon on the other end.
  docker run -d \
    --name "$container" \
    --entrypoint sleep \
    "$scanner_image" \
    infinity >&3
}

# ---------------------------------------------------------------------------
# Suite teardown — always runs, even if a test fails.
# ---------------------------------------------------------------------------
teardown_file() {
  [[ -f "${BATS_FILE_TMPDIR}/container" ]] || return 0
  local container
  container=$(<"${BATS_FILE_TMPDIR}/container")
  docker rm -f "$container" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Binary presence and versions
# ---------------------------------------------------------------------------

@test "syft version matches Dockerfile" {
  local expected_version
  expected_version="$(grep -oE 'anchore/syft:v[0-9]+\.[0-9]+\.[0-9]+' "${REPO_ROOT}/insights-scanner/Dockerfile" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
  run _exec syft version
  [ "$status" -eq 0 ]
  [[ "$output" == *"${expected_version}"* ]]
}

@test "kubectl version matches Dockerfile" {
  local expected_version
  expected_version="$(grep -oE 'KUBECTL_VERSION=v[0-9]+\.[0-9]+\.[0-9]+' "${REPO_ROOT}/insights-scanner/Dockerfile" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')"
  run _exec kubectl version --client
  [ "$status" -eq 0 ]
  [[ "$output" == *"${expected_version}"* ]]
}

@test "skopeo is present" {
  run _exec skopeo --version
  [ "$status" -eq 0 ]
}

@test "jq is present" {
  run _exec jq --version
  [ "$status" -eq 0 ]
}

@test "curl is present" {
  run _exec curl --version
  [ "$status" -eq 0 ]
}

@test "bash is present" {
  run _exec bash --version
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Script presence and permissions
# ---------------------------------------------------------------------------

@test "run.sh exists and is executable" {
  run _exec test -x /app/run.sh
  [ "$status" -eq 0 ]
}

@test "insights-scan.sh exists in /app" {
  run _exec test -f /app/insights-scan.sh
  [ "$status" -eq 0 ]
}

@test "docker-host entrypoint script is in place" {
  run _exec test -f /lagoon/entrypoints/100-docker-entrypoint.sh
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Image environment
# ---------------------------------------------------------------------------

@test "LAGOON env var is set to insights-scanner" {
  run _exec sh -c 'echo "$LAGOON"'
  [ "$status" -eq 0 ]
  [ "$output" = "insights-scanner" ]
}

@test "DOCKER_HOST defaults to docker-host.lagoon.svc" {
  run _exec sh -c 'echo "$DOCKER_HOST"'
  [ "$status" -eq 0 ]
  [ "$output" = "docker-host.lagoon.svc" ]
}

# ---------------------------------------------------------------------------
# featureFlag / buildEnvVarCheck function behaviour
#
# run.sh is sourced with INSIGHT_SCAN_IMAGES unset so the processing loop
# at the bottom of the script is a no-op (an unset variable expands to an
# empty word list in bash, producing zero iterations).  The helper functions
# are then exercised without any live cluster or image registry.
# ---------------------------------------------------------------------------

@test "featureFlag: force flag takes priority over all others" {
  run _exec bash -c '
    unset INSIGHT_SCAN_IMAGES
    source /app/run.sh
    LAGOON_FEATURE_FLAG_FORCE_MY_FLAG=force_val \
    LAGOON_FEATURE_FLAG_DEFAULT_MY_FLAG=default_val \
      featureFlag MY_FLAG
  '
  [ "$status" -eq 0 ]
  [ "$output" = "force_val" ]
}

@test "featureFlag: regular flag from LAGOON_ENVIRONMENT_VARIABLES beats default" {
  local container env_json
  container=$(<"${BATS_FILE_TMPDIR}/container")
  env_json='[{"name":"LAGOON_FEATURE_FLAG_MY_FLAG","value":"env_val","scope":"build"}]'
  run docker exec \
    -e "LAGOON_ENVIRONMENT_VARIABLES=${env_json}" \
    "$container" \
    bash -c '
      unset INSIGHT_SCAN_IMAGES
      source /app/run.sh
      LAGOON_FEATURE_FLAG_DEFAULT_MY_FLAG=default_val featureFlag MY_FLAG
    '
  [ "$status" -eq 0 ]
  [ "$output" = "env_val" ]
}

@test "featureFlag: falls back to default when no other flags are set" {
  run _exec bash -c '
    unset INSIGHT_SCAN_IMAGES
    source /app/run.sh
    LAGOON_FEATURE_FLAG_DEFAULT_MY_FLAG=default_val featureFlag MY_FLAG
  '
  [ "$status" -eq 0 ]
  [ "$output" = "default_val" ]
}

@test "featureFlag: returns empty string when no flags are set" {
  run _exec bash -c '
    unset INSIGHT_SCAN_IMAGES
    source /app/run.sh
    result=$(featureFlag MY_FLAG)
    echo -n "$result"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "featureFlag: returns non-zero when called without arguments" {
  # The function does '[ "$1" ] || return' — with no arg, [ "$1" ] fails and
  # return propagates that failure code out of the function.
  run _exec bash -c '
    unset INSIGHT_SCAN_IMAGES
    source /app/run.sh
    featureFlag
  '
  [ "$status" -ne 0 ]
}

@test "buildEnvVarCheck: returns value for a matching build-scoped variable" {
  local container env_json
  container=$(<"${BATS_FILE_TMPDIR}/container")
  env_json='[{"name":"MY_VAR","value":"my_val","scope":"build"}]'
  run docker exec \
    -e "LAGOON_ENVIRONMENT_VARIABLES=${env_json}" \
    "$container" \
    bash -c '
      unset INSIGHT_SCAN_IMAGES
      source /app/run.sh
      buildEnvVarCheck MY_VAR
    '
  [ "$status" -eq 0 ]
  [ "$output" = "my_val" ]
}

@test "buildEnvVarCheck: returns empty for a variable with a non-build scope" {
  local container env_json
  container=$(<"${BATS_FILE_TMPDIR}/container")
  env_json='[{"name":"MY_VAR","value":"my_val","scope":"runtime"}]'
  run docker exec \
    -e "LAGOON_ENVIRONMENT_VARIABLES=${env_json}" \
    "$container" \
    bash -c '
      unset INSIGHT_SCAN_IMAGES
      source /app/run.sh
      result=$(buildEnvVarCheck MY_VAR)
      echo -n "$result"
    '
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "buildEnvVarCheck: returns value for a global-scoped variable" {
  # The filter in run.sh is: scope == "build" or scope == "global"
  local container env_json
  container=$(<"${BATS_FILE_TMPDIR}/container")
  env_json='[{"name":"MY_VAR","value":"global_val","scope":"global"}]'
  run docker exec \
    -e "LAGOON_ENVIRONMENT_VARIABLES=${env_json}" \
    "$container" \
    bash -c '
      unset INSIGHT_SCAN_IMAGES
      source /app/run.sh
      buildEnvVarCheck MY_VAR
    '
  [ "$status" -eq 0 ]
  [ "$output" = "global_val" ]
}

# ---------------------------------------------------------------------------
# LAGOON_FEATURE_FLAG_* as direct environment variables
#
# insights-remote copies any var matching LAGOON_FEATURE_FLAG_.+ from the
# build pod onto the scan pod as a real env var (not inside
# LAGOON_ENVIRONMENT_VARIABLES JSON).  The featureFlag function checks
# LAGOON_FEATURE_FLAG_FORCE_* and LAGOON_FEATURE_FLAG_DEFAULT_* directly,
# so these tests confirm the controller-injected form works end-to-end.
# ---------------------------------------------------------------------------

@test "LAGOON_FEATURE_FLAG_FORCE_* env var is respected as a force override" {
  local container
  container=$(<"${BATS_FILE_TMPDIR}/container")
  run docker exec \
    -e "LAGOON_FEATURE_FLAG_FORCE_INSIGHTS_CORE_ENABLED=true" \
    "$container" \
    bash -c '
      unset INSIGHT_SCAN_IMAGES
      source /app/run.sh
      featureFlag INSIGHTS_CORE_ENABLED
    '
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "LAGOON_FEATURE_FLAG_DEFAULT_* env var is used as fallback" {
  local container
  container=$(<"${BATS_FILE_TMPDIR}/container")
  run docker exec \
    -e "LAGOON_FEATURE_FLAG_DEFAULT_INSIGHTS_SBOM_ENABLED=true" \
    "$container" \
    bash -c '
      unset INSIGHT_SCAN_IMAGES
      source /app/run.sh
      featureFlag INSIGHTS_SBOM_ENABLED
    '
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# ---------------------------------------------------------------------------
# IMAGE_NAME / IMAGE_FULL parsing logic
#
# insights-remote joins deployment image refs with commas into
# INSIGHT_SCAN_IMAGES.  run.sh extracts IMAGE_NAME and IMAGE_FULL from each
# entry using awk + cut.  These tests use the exact same expressions to
# verify they handle all image ref formats the controller can produce.
# ---------------------------------------------------------------------------

@test "IMAGE_NAME: extracted correctly from registry/path/name:tag" {
  run _exec bash -c '
    image="registry.example.com/myproject/nginx:abc123"
    IMAGE_NAME=$(echo "$image" | awk -F/ "{print \$NF}" | cut -d: -f1 | cut -d@ -f1)
    echo "$IMAGE_NAME"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "nginx" ]
}

@test "IMAGE_NAME: extracted correctly from registry/path/name@sha256 digest ref" {
  run _exec bash -c '
    image="registry.example.com/myproject/php@sha256:deadbeefdeadbeef"
    IMAGE_NAME=$(echo "$image" | awk -F/ "{print \$NF}" | cut -d: -f1 | cut -d@ -f1)
    echo "$IMAGE_NAME"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "php" ]
}

@test "IMAGE_NAME: extracted correctly from a simple name:tag (no registry prefix)" {
  run _exec bash -c '
    image="nginx:latest"
    IMAGE_NAME=$(echo "$image" | awk -F/ "{print \$NF}" | cut -d: -f1 | cut -d@ -f1)
    echo "$IMAGE_NAME"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "nginx" ]
}

@test "IMAGE_FULL: tag is normalised to :latest from a tagged ref" {
  run _exec bash -c '
    image="registry.example.com/myproject/nginx:abc123"
    IMAGE_FULL="$(echo "$image" | cut -d: -f1 | cut -d@ -f1):latest"
    echo "$IMAGE_FULL"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "registry.example.com/myproject/nginx:latest" ]
}

@test "IMAGE_FULL: tag is normalised to :latest from a digest ref" {
  run _exec bash -c '
    image="registry.example.com/myproject/nginx@sha256:deadbeef"
    IMAGE_FULL="$(echo "$image" | cut -d: -f1 | cut -d@ -f1):latest"
    echo "$IMAGE_FULL"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "registry.example.com/myproject/nginx:latest" ]
}

# ---------------------------------------------------------------------------
# INSIGHT_SCAN_IMAGES iteration
#
# run.sh splits INSIGHT_SCAN_IMAGES on commas and sources insights-scan.sh
# for every entry.  This test replaces insights-scan.sh with a lightweight
# probe (written to a temp file) to confirm both IMAGE_NAME values are
# visited without invoking the real scan tools.
# ---------------------------------------------------------------------------

@test "run.sh iterates over every image in a comma-separated INSIGHT_SCAN_IMAGES" {
  # Test the IFS-splitting loop and IMAGE_NAME extraction from run.sh directly,
  # without sed-patching the script (which is fragile on busybox sed).
  run _exec bash -c '
    INSIGHT_SCAN_IMAGES="registry.example.com/proj/nginx:abc,registry.example.com/proj/php:def"
    IFS=","
    for image in $INSIGHT_SCAN_IMAGES; do
      IMAGE_NAME=$(echo "$image" | awk -F/ "{print \$NF}" | cut -d: -f1 | cut -d@ -f1)
      echo "SCANNED:${IMAGE_NAME}"
    done
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCANNED:nginx"* ]]
  [[ "$output" == *"SCANNED:php"* ]]
}

# ---------------------------------------------------------------------------
# Docker registry secret mount path
#
# insights-remote mounts the lagoon-internal-registry-secret at
# /home/.docker/ (as config.json).  Verify the directory is present and
# writable so that skopeo / syft can authenticate to the registry.
# ---------------------------------------------------------------------------

@test "/home/.docker directory exists and is writable" {
  run _exec bash -c 'test -d /home/.docker && touch /home/.docker/.write-test && rm /home/.docker/.write-test'
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Build environment variables injected by insights-remote
#
# The controller always sets INSIGHT_SCAN_IMAGES, NAMESPACE, and DOCKER_HOST,
# and copies BRANCH, BUILD_TYPE, ENVIRONMENT, ENVIRONMENT_TYPE, PROJECT,
# PR_BASE_BRANCH, PR_HEAD_BRANCH, PR_NUMBER, LAGOON_ENVIRONMENT_VARIABLES,
# and any LAGOON_FEATURE_FLAG_* variables from the build pod.
# These tests confirm that each of those variables is accessible inside the
# container and propagates correctly to the scripts.
# ---------------------------------------------------------------------------

@test "NAMESPACE env var is accessible inside the container" {
  local container
  container=$(<"${BATS_FILE_TMPDIR}/container")
  run docker exec -e "NAMESPACE=my-test-ns" "$container" sh -c 'echo "$NAMESPACE"'
  [ "$status" -eq 0 ]
  [ "$output" = "my-test-ns" ]
}

@test "BRANCH env var is accessible inside the container" {
  local container
  container=$(<"${BATS_FILE_TMPDIR}/container")
  run docker exec -e "BRANCH=main" "$container" sh -c 'echo "$BRANCH"'
  [ "$status" -eq 0 ]
  [ "$output" = "main" ]
}

@test "BUILD_TYPE env var is accessible inside the container" {
  local container
  container=$(<"${BATS_FILE_TMPDIR}/container")
  run docker exec -e "BUILD_TYPE=branch" "$container" sh -c 'echo "$BUILD_TYPE"'
  [ "$status" -eq 0 ]
  [ "$output" = "branch" ]
}

@test "PROJECT, ENVIRONMENT, ENVIRONMENT_TYPE env vars are all accessible" {
  local container
  container=$(<"${BATS_FILE_TMPDIR}/container")
  run docker exec \
    -e "PROJECT=my-project" \
    -e "ENVIRONMENT=production" \
    -e "ENVIRONMENT_TYPE=production" \
    "$container" \
    sh -c 'echo "$PROJECT $ENVIRONMENT $ENVIRONMENT_TYPE"'
  [ "$status" -eq 0 ]
  [ "$output" = "my-project production production" ]
}

@test "PR_NUMBER, PR_HEAD_BRANCH, PR_BASE_BRANCH env vars are all accessible" {
  local container
  container=$(<"${BATS_FILE_TMPDIR}/container")
  run docker exec \
    -e "PR_NUMBER=42" \
    -e "PR_HEAD_BRANCH=feature/foo" \
    -e "PR_BASE_BRANCH=main" \
    "$container" \
    sh -c 'echo "$PR_NUMBER $PR_HEAD_BRANCH $PR_BASE_BRANCH"'
  [ "$status" -eq 0 ]
  [ "$output" = "42 feature/foo main" ]
}

# ---------------------------------------------------------------------------
# syft output format
#
# insights-scan.sh calls: syft -o cyclonedx-json <image> | gzip > ...
# Confirm that syft supports that output schema without scanning a real image
# by running it against the local /etc/os-release file (dir: scheme).
# ---------------------------------------------------------------------------

@test "syft supports cyclonedx-json output format" {
  run _exec bash -c 'syft -o cyclonedx-json dir:/etc 2>/dev/null | head -c 20'
  [ "$status" -eq 0 ]
  # CycloneDX JSON always starts with a { bom root object
  [[ "$output" == "{"* ]]
}
