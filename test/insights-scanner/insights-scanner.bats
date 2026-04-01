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
  [ -n "$expected_version" ] # guard: grep must have matched
  run _exec syft version
  [ "$status" -eq 0 ]
  [[ "$output" == *"${expected_version}"* ]]
}

@test "kubectl version matches Dockerfile" {
  local expected_version
  expected_version="$(grep -oE 'KUBECTL_VERSION=v[0-9]+\.[0-9]+\.[0-9]+' "${REPO_ROOT}/insights-scanner/Dockerfile" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')"
  [ -n "$expected_version" ] # guard: grep must have matched
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
    LAGOON_ENVIRONMENT_VARIABLES="[]"
    source /app/run.sh
    LAGOON_FEATURE_FLAG_DEFAULT_MY_FLAG=default_val featureFlag MY_FLAG
  '
  [ "$status" -eq 0 ]
  [ "$output" = "default_val" ]
}

@test "featureFlag: returns empty string when no flags are set" {
  run _exec bash -c '
    unset INSIGHT_SCAN_IMAGES
    LAGOON_ENVIRONMENT_VARIABLES="[]"
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
    -e "LAGOON_ENVIRONMENT_VARIABLES=[]" \
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
    -e "LAGOON_ENVIRONMENT_VARIABLES=[]" \
    "$container" \
    bash -c '
      unset INSIGHT_SCAN_IMAGES
      source /app/run.sh
      featureFlag INSIGHTS_SBOM_ENABLED
    '
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "featureFlag: INSIGHTS_SBOM_ENABLED read from LAGOON_ENVIRONMENT_VARIABLES JSON" {
  # Simulates an operator setting LAGOON_FEATURE_FLAG_INSIGHTS_SBOM_ENABLED as
  # a Lagoon project build variable (scope: build).  insights-remote copies the
  # entire LAGOON_ENVIRONMENT_VARIABLES blob onto the scan pod; featureFlag must
  # retrieve the value via buildEnvVarCheck without any direct env var present.
  local container env_json
  container=$(<"${BATS_FILE_TMPDIR}/container")
  env_json='[{"name":"LAGOON_FEATURE_FLAG_INSIGHTS_SBOM_ENABLED","value":"true","scope":"build"}]'
  run docker exec \
    -e "LAGOON_ENVIRONMENT_VARIABLES=${env_json}" \
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
# run.sh echoes "With image name: $IMAGE_NAME" and "Processing image: $IMAGE_FULL"
# before sourcing insights-scan.sh.  By running run.sh directly with a
# controlled INSIGHT_SCAN_IMAGES we verify the parsing without duplicating the
# awk/cut expressions.  stderr is suppressed so skopeo/kubectl failures
# (expected without a live cluster) don't pollute the captured output.
# ---------------------------------------------------------------------------

@test "image parsing: tag ref yields correct IMAGE_NAME and :latest IMAGE_FULL" {
  run _exec bash -c '
    INSIGHT_SCAN_IMAGES="registry.example.com/myproject/nginx:abc123" \
      bash /app/run.sh 2>/dev/null
  '
  [[ "$output" == *"With image name: nginx"* ]]
  [[ "$output" == *"Processing image: registry.example.com/myproject/nginx:latest"* ]]
}

@test "image parsing: digest ref yields correct IMAGE_NAME and :latest IMAGE_FULL" {
  run _exec bash -c '
    INSIGHT_SCAN_IMAGES="registry.example.com/myproject/php@sha256:deadbeef" \
      bash /app/run.sh 2>/dev/null
  '
  [[ "$output" == *"With image name: php"* ]]
  [[ "$output" == *"Processing image: registry.example.com/myproject/php:latest"* ]]
}

@test "run.sh iterates over every image in a comma-separated INSIGHT_SCAN_IMAGES" {
  run _exec bash -c '
    INSIGHT_SCAN_IMAGES="registry.example.com/proj/nginx:abc,registry.example.com/proj/php:def" \
      bash /app/run.sh 2>/dev/null
  '
  [[ "$output" == *"With image name: nginx"* ]]
  [[ "$output" == *"With image name: php"* ]]
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
