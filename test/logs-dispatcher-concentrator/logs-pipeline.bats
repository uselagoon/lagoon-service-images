#!/usr/bin/env bats
# logs-pipeline.bats — BATS integration tests for logs-dispatcher + logs-concentrator.
#
# Requires bats-core >= 1.5.0 (for setup_file / teardown_file).
# Install: https://bats-core.readthedocs.io/en/stable/installation.html
#
# Usage (local):
#   bats test/logs-dispatcher-concentrator/logs-pipeline.bats
#
# Environment variables (all optional — same as run-tests.sh):
#   DISPATCHER_IMAGE     (default: lagoon/logs-dispatcher:latest)
#   CONCENTRATOR_IMAGE   (default: lagoon/logs-concentrator:latest)
#   DISPATCHER_HTTP_PORT (default: 9880)
#   SKIP_BUILD           set to "true" to skip docker build
#   BUILD_PLATFORM       (optional) e.g. linux/amd64 or linux/arm64; omit to
#                        let Docker pick the native host platform automatically

# ---------------------------------------------------------------------------
# File-level constants — sourced into every test subshell by bats-core.
# ---------------------------------------------------------------------------
COMPOSE_FILE="${BATS_TEST_DIRNAME}/docker-compose.yml"
REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

# ---------------------------------------------------------------------------
# Helper: poll until the named compose service reports "healthy".
# Reads project name from BATS_FILE_TMPDIR so it works in any context.
# ---------------------------------------------------------------------------
_wait_healthy() {
  local service="$1"
  local timeout="${2:-120}"
  local project compose_file elapsed=0

  project=$(<"${BATS_FILE_TMPDIR}/project")
  compose_file="${BATS_TEST_DIRNAME}/docker-compose.yml"

  while [[ $elapsed -lt $timeout ]]; do
    local container_id status
    container_id=$(docker compose -p "$project" -f "$compose_file" \
      ps -q "$service" 2>/dev/null || true)

    if [[ -n "$container_id" ]]; then
      status=$(docker inspect \
        --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
        "$container_id" 2>/dev/null || echo "unknown")
      [[ "$status" == "healthy" ]] && return 0
    fi

    sleep 5
    elapsed=$((elapsed + 5))
  done
  return 1
}

# ---------------------------------------------------------------------------
# Suite setup — runs once before all tests.
# Writes shared state to BATS_FILE_TMPDIR (survives into test subshells).
# ---------------------------------------------------------------------------
setup_file() {
  local dispatcher_image="${DISPATCHER_IMAGE:-lagoon/logs-dispatcher:latest}"
  local concentrator_image="${CONCENTRATOR_IMAGE:-lagoon/logs-concentrator:latest}"
  local http_port="${DISPATCHER_HTTP_PORT:-9880}"
  local skip_build="${SKIP_BUILD:-false}"
  local build_platform="${BUILD_PLATFORM:-}" # empty = let Docker pick natively

  # Build platform flag — only set when explicitly requested so we never
  # force a cross-platform build that conflicts with a locally-cached base image.
  local platform_flag=()
  [[ -n "$build_platform" ]] && platform_flag=("--platform" "$build_platform")

  local run_id project
  run_id="$(date +%s)-$$"
  project="logs-test-bats-${run_id}"

  # Persist values for tests and teardown_file.
  echo "$project"   > "${BATS_FILE_TMPDIR}/project"
  echo "$run_id"    > "${BATS_FILE_TMPDIR}/run_id"
  echo "$http_port" > "${BATS_FILE_TMPDIR}/http_port"

  # Optional build.
  if [[ "$skip_build" != "true" ]]; then
    docker build \
      "${platform_flag[@]}" \
      -t "$dispatcher_image" \
      "${REPO_ROOT}/logs-dispatcher" >&3
    docker build \
      "${platform_flag[@]}" \
      -t "$concentrator_image" \
      "${REPO_ROOT}/logs-concentrator" >&3
  fi

  # Start the compose stack.
  DISPATCHER_IMAGE="$dispatcher_image" \
  CONCENTRATOR_IMAGE="$concentrator_image" \
  DISPATCHER_HTTP_PORT="$http_port" \
    docker compose -p "$project" -f "$COMPOSE_FILE" up -d >&3 2>&3

  # Block until both services are healthy (uses the helper above, which
  # reads 'project' from BATS_FILE_TMPDIR).
  _wait_healthy logs-concentrator 120 \
    || { echo "logs-concentrator never became healthy" >&3; return 1; }
  _wait_healthy logs-dispatcher 120 \
    || { echo "logs-dispatcher never became healthy" >&3; return 1; }

  # Inject varied event types via the dispatcher's HTTP input to exercise
  # different payload shapes the pipeline is expected to handle.
  local endpoint="http://localhost:${http_port}/test.integration"

  # 1. Simple key-value log message (baseline).
  curl -sf -X POST "$endpoint" \
    -H 'Content-Type: application/json' \
    -d "{\"message\":\"simple-${run_id}\",\"seq\":1}"

  # 2. Kubernetes-style structured log with pod metadata fields.
  curl -sf -X POST "$endpoint" \
    -H 'Content-Type: application/json' \
    -d "{\"log\":\"kubernetes-${run_id}\",\"kubernetes\":{\"namespace_name\":\"test-ns\",\"pod_name\":\"web-abc123\",\"container_name\":\"nginx\",\"labels\":{\"app\":\"web\",\"env\":\"test\"}}}"

  # 3. Application log with severity, logger name and a stack-trace style message.
  curl -sf -X POST "$endpoint" \
    -H 'Content-Type: application/json' \
    -d "{\"level\":\"ERROR\",\"logger\":\"com.example.App\",\"message\":\"applog-${run_id}\",\"stack_trace\":\"java.lang.NullPointerException\\n\\tat com.example.App.run(App.java:42)\"}"

  # 4. Event with special characters and unicode in the payload.
  curl -sf -X POST "$endpoint" \
    -H 'Content-Type: application/json' \
    -d "{\"message\":\"special-${run_id}\",\"body\":\"caf\\u00e9 \\u00e0 la mode & <b>bold<\\/b> \\\"quoted\\\"\"}"

  # 5. Minimal single-field event.
  curl -sf -X POST "$endpoint" \
    -H 'Content-Type: application/json' \
    -d "{\"message\":\"minimal-${run_id}\"}"

  # Allow time for the pipeline to propagate events through to the file sink.
  sleep 8

  # Capture the concentrator file output and service logs for the assertion
  # tests to reference — written to files so test subshells can read them.
  docker compose -p "$project" -f "$COMPOSE_FILE" \
    exec -T logs-concentrator \
    sh -c 'cat /fluentd/log/test-output*.log 2>/dev/null || true' \
    > "${BATS_FILE_TMPDIR}/concentrator_file_output"

  docker compose -p "$project" -f "$COMPOSE_FILE" \
    logs --no-color logs-concentrator \
    > "${BATS_FILE_TMPDIR}/concentrator_logs" 2>&1 || true

  docker compose -p "$project" -f "$COMPOSE_FILE" \
    logs --no-color logs-dispatcher \
    > "${BATS_FILE_TMPDIR}/dispatcher_logs" 2>&1 || true
}

# ---------------------------------------------------------------------------
# Suite teardown — always runs, even if a test fails.
# ---------------------------------------------------------------------------
teardown_file() {
  # Gracefully handle the case where setup_file failed before writing 'project'.
  [[ -f "${BATS_FILE_TMPDIR}/project" ]] || return 0
  local project
  project=$(<"${BATS_FILE_TMPDIR}/project")
  docker compose -p "$project" -f "$COMPOSE_FILE" \
    down -v --remove-orphans 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "logs-concentrator container is healthy" {
  local project
  project=$(<"${BATS_FILE_TMPDIR}/project")
  local container_id
  container_id=$(docker compose -p "$project" -f "$COMPOSE_FILE" \
    ps -q logs-concentrator)
  run docker inspect \
    --format='{{.State.Health.Status}}' \
    "$container_id"
  [[ "$output" == "healthy" ]]
}

@test "logs-dispatcher container is healthy" {
  local project
  project=$(<"${BATS_FILE_TMPDIR}/project")
  local container_id
  container_id=$(docker compose -p "$project" -f "$COMPOSE_FILE" \
    ps -q logs-dispatcher)
  run docker inspect \
    --format='{{.State.Health.Status}}' \
    "$container_id"
  [[ "$output" == "healthy" ]]
}

@test "simple key-value event is received by the concentrator" {
  local run_id
  run_id=$(<"${BATS_FILE_TMPDIR}/run_id")
  grep -qF "simple-${run_id}" "${BATS_FILE_TMPDIR}/concentrator_file_output" \
    || grep -qF "simple-${run_id}" "${BATS_FILE_TMPDIR}/concentrator_logs"
}

@test "kubernetes-style structured event is received by the concentrator" {
  local run_id
  run_id=$(<"${BATS_FILE_TMPDIR}/run_id")
  grep -qF "kubernetes-${run_id}" "${BATS_FILE_TMPDIR}/concentrator_file_output" \
    || grep -qF "kubernetes-${run_id}" "${BATS_FILE_TMPDIR}/concentrator_logs"
}

@test "application log event with severity and stack trace is received by the concentrator" {
  local run_id
  run_id=$(<"${BATS_FILE_TMPDIR}/run_id")
  grep -qF "applog-${run_id}" "${BATS_FILE_TMPDIR}/concentrator_file_output" \
    || grep -qF "applog-${run_id}" "${BATS_FILE_TMPDIR}/concentrator_logs"
}

@test "event with special characters and unicode is received by the concentrator" {
  local run_id
  run_id=$(<"${BATS_FILE_TMPDIR}/run_id")
  grep -qF "special-${run_id}" "${BATS_FILE_TMPDIR}/concentrator_file_output" \
    || grep -qF "special-${run_id}" "${BATS_FILE_TMPDIR}/concentrator_logs"
}

@test "minimal single-field event is received by the concentrator" {
  local run_id
  run_id=$(<"${BATS_FILE_TMPDIR}/run_id")
  grep -qF "minimal-${run_id}" "${BATS_FILE_TMPDIR}/concentrator_file_output" \
    || grep -qF "minimal-${run_id}" "${BATS_FILE_TMPDIR}/concentrator_logs"
}

@test "dispatcher forward plugin has no errors" {
  ! grep -qiE '\[error\].*out_forward' "${BATS_FILE_TMPDIR}/dispatcher_logs"
}
