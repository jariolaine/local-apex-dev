#!/usr/bin/env bash

declare -a E2E_PHASE_NAMES=()
declare -a E2E_PHASE_FUNCTIONS=()

# Persist only values produced by completed phases that later phases need.
# Credentials and normal runner configuration are intentionally reconstructed
# on each invocation rather than written to the resume-state file.
E2E_STATE_VARIABLES=(
  E2E_OLD_APEX_DB_VERSION
)

setup_host_identity_args=()

fail() {
  echo "FAIL : $*" >&2
  return 1
}

pass() {
  echo "PASS : $*"
}

info() {
  echo "INFO : $*"
}

phase() {
  E2E_PHASE=$((E2E_PHASE + 1))
  printf '\n===== E2E %02d/%02d : %s =====\n' "$E2E_PHASE" "$E2E_PHASE_TOTAL" "$*"
}

contains() {
  local target="$1"
  shift
  local element
  for element in "$@"; do
    if [[ "$element" == "$target" ]]; then
      return 0  # Found (Exit code 0 means "true" in Bash)
    fi
  done
  return 1  # Not found (Exit code 1 means "false")
}

# Emit failure diagnostics and retain resume metadata.
# Successful cleanup is handled explicitly by the main runner.
on_exit() {
  local rc=$?
  local failed_function=""

  if (( rc != 0 )); then
    dump_logs

    echo
    echo \
      "FAIL : E2E suite stopped during phase ${E2E_PHASE}/${E2E_PHASE_TOTAL}." \
      >&2

    if [[ -s "$E2E_RESUME_PHASE_FILE" ]]; then
      failed_function="$(
        < "$E2E_RESUME_PHASE_FILE"
      )"

      echo \
        "INFO : Failed phase function: ${failed_function}" \
        >&2

      echo \
        "INFO : Resume with:" \
        >&2

      echo \
        "       E2E_ALLOW_DESTRUCTIVE=Y E2E_RESUME=Y ./tests/e2e/run.sh" \
        >&2
    fi
  fi
}

is_true() {
  case "${1^^}" in
    Y|YES|TRUE|1) return 0 ;;
    *) return 1 ;;
  esac
}

is_version() {
  local actual expected
  actual="$1"
  expected="$2"
  [[ "$actual" == "$expected" ||
     "$actual" == "${expected}."* ]]
}

set_env_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp

  tmp="$(mktemp)"

  awk -v key="$key" -v value="$value" '
    BEGIN { done = 0 }
    $0 ~ "^[[:space:]]*#?[[:space:]]*" key "=" {
      if (!done) {
        print key "=" value
        done = 1
      }
      next
    }
    { print }
    END {
      if (!done) print key "=" value
    }
  ' "$file" > "$tmp"

  mv "$tmp" "$file"
}

initialize_e2e_logging() {
  local log_dir

  log_dir="$(dirname "$E2E_LOG_FILE")"
  mkdir -p "$log_dir"

  # A fresh run starts a new log. A resumed run appends to the log from
  # the failed run so the complete execution history remains together.
  if ! is_true "$E2E_RESUME"; then
    : > "$E2E_LOG_FILE"
  fi

  exec > >(
    tee -a "$E2E_LOG_FILE"
  ) 2>&1

  echo
  echo "================================================================================"
  if is_true "$E2E_RESUME"; then
    echo "E2E test resumed: $(date '+%Y-%m-%d %H:%M:%S %z')"
  else
    echo "E2E test started: $(date '+%Y-%m-%d %H:%M:%S %z')"
  fi
  echo "================================================================================"
}

# Phase function names are persisted as resume identifiers.
# Keep them unique and stable when possible so failed runs remain resumable.
register_phase() {
  local name="$1"
  local function_name="$2"

  [[ -n "$name" ]] ||
    fail "Cannot register an E2E phase without a name."

  declare -F "$function_name" >/dev/null ||
    fail "E2E phase function does not exist: $function_name"

  if contains "$function_name" "${E2E_PHASE_FUNCTIONS[@]}"; then
    fail "E2E duplicate function name: $function_name"
  fi

  E2E_PHASE_NAMES+=("$name")
  E2E_PHASE_FUNCTIONS+=("$function_name")
}


# Define docker-compose wrapper functions to simplify command execution with consistent parameters
compose_base() {
  docker compose \
    -p "$E2E_PROJECT_NAME" \
    --project-directory "$REPO_ROOT" \
    "${BASE_COMPOSE_FILES[@]}" \
    "$@"
}

compose_ollama() {
  docker compose \
    -p "$E2E_PROJECT_NAME" \
    --project-directory "$REPO_ROOT" \
    "${OLLAMA_COMPOSE_FILES[@]}" \
    "$@"
}

# setup.sh refuses to run while runtime services are active.
# Case phases must stop the relevant stack before invoking this helper.
run_setup() {
  compose_base run --rm \
    "${setup_host_identity_args[@]}" \
    "$@" \
    setup
}

wait_for_services() {
  local compose_fn="$1"
  local timeout_seconds="$2"
  shift 2

  local service

  for service in "$@"; do
    wait_for_service_health \
      "$compose_fn" \
      "$service" \
      "$timeout_seconds"
  done
}

start_base_services() {
  compose_base up -d db ords
  wait_for_services \
    compose_base \
    "$E2E_SERVICE_TIMEOUT" \
    db \
    ords
}

# Apply test environment variables to .env file
apply_test_environment() {
  [[ -f .env ]] || fail ".env was not generated."
  set_env_value .env ORACLE_PWD "$E2E_ORACLE_PWD"
  set_env_value .env HOST_DB_BINDING "$E2E_DB_HOST_BINDING"
  set_env_value .env HOST_ORDS_BINDING "$E2E_ORDS_HOST_BINDING"
}

checksum_file() {
  local file="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file"
  else
    fail "Neither sha256sum nor shasum is available."
  fi
}

generated_files_checksums() {
  local file

  for file in \
    .env \
    apex_instance_parameters.yaml \
    apex_workspaces.yaml \
    ssl/ca.cer \
    ssl/server.cer \
    ssl/server.key \
    ssl/fullChain.cer
  do
    [[ -f "$file" ]] ||
      fail "Expected generated file is missing: $file"

    checksum_file "$file"
  done
}

wait_for_service_health() {
  local compose_fn="$1"
  local service="$2"
  local timeout_seconds="${3:-1800}"
  local start now id health status

  start="$(date +%s)"

  while true; do
    id="$($compose_fn ps -q "$service" 2>/dev/null || true)"

    if [[ -n "$id" ]]; then
      status="$(docker inspect -f '{{.State.Status}}' "$id" 2>/dev/null || true)"
      health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$id" 2>/dev/null || true)"

      if [[ "$status" == "running" && ( "$health" == "healthy" || "$health" == "none" ) ]]; then
        pass "$service is running${health:+ with health=$health}."
        return 0
      fi

      if [[ "$health" == "unhealthy" || "$status" == "exited" || "$status" == "dead" ]]; then
        fail "$service entered state status=$status health=$health."
        return 1
      fi
    fi

    now="$(date +%s)"
    if (( now - start >= timeout_seconds )); then
      fail "Timed out waiting for $service after ${timeout_seconds}s."
      return 1
    fi

    sleep 10
  done
}

wait_for_model() {
  local model="$1"
  local timeout_seconds="${2:-1800}"
  local start now

  start="$(date +%s)"

  while true; do
    if compose_ollama exec -T ollama ollama list 2>/dev/null \
      | awk 'NR > 1 {print $1}' \
      | grep -Fxq "$model"; then
      pass "Ollama model is available: $model"
      return 0
    fi

    now="$(date +%s)"
    if (( now - start >= timeout_seconds )); then
      fail "Timed out waiting for Ollama model: $model"
      return 1
    fi

    sleep 10
  done
}

# Run a SQL test script in the database container through the selected
# Compose stack and connection mode.
#
# Usage:
#   _run_sql <compose_function> <sys|schema> <script> [script arguments...]
#
# Variables inside the container command are intentionally expanded by Bash
# in the database container, not by the host shell.
# shellcheck disable=SC2016
_run_sql() {
  local compose_fn="$1"
  local connection_mode="$2"
  local script="$3"
  shift 3

  local -a exec_args=(exec -T)

  case "$connection_mode" in
    sys)
      ;;
    schema)
      exec_args+=(
        -e "E2E_SCHEMA=${E2E_SCHEMA}"
        -e "E2E_SCHEMA_PASSWORD=${E2E_SCHEMA_PASSWORD}"
        -e "E2E_ORACLE_PDB=${E2E_ORACLE_PDB}"
      )
      ;;
    *)
      fail "Unsupported SQL connection mode: $connection_mode"
      return 1
      ;;
  esac

  "$compose_fn" "${exec_args[@]}" db bash -c '
    connection_mode="$1"
    script="$2"
    shift 2

    case "$connection_mode" in
      sys)
        connection=(/ as sysdba)
        ;;
      schema)
        connection=(
          "${E2E_SCHEMA}/${E2E_SCHEMA_PASSWORD}@localhost:1521/${E2E_ORACLE_PDB}"
        )
        ;;
      *)
        echo "FAIL : Unsupported SQL connection mode: ${connection_mode}" >&2
        exit 2
        ;;
    esac

    exec sqlplus -L -S \
      "${connection[@]}" \
      "@/e2e/sql/${script}" \
      "$@"
  ' _ "$connection_mode" "$script" "$@"
}

run_sys_sql() {
  _run_sql compose_base sys "$@"
}

run_schema_sql() {
  _run_sql compose_base schema "$@"
}

run_sys_sql_ollama() {
  _run_sql compose_ollama sys "$@"
}

run_schema_sql_ollama() {
  _run_sql compose_ollama schema "$@"
}

run_playwright() {
  local name="$1"
  shift

  local -a playwright_command=()
  local -a environment_args=()

  if (( $# > 0 )); then
    playwright_command=(
      npx playwright test "$@"
    )
  fi

  if [[ -n "${DATABASE_ACTIONS_USER:-}" ]]; then
    environment_args+=(
      -e "DATABASE_ACTIONS_USER=${DATABASE_ACTIONS_USER}"
    )
  fi

  if [[ -n "${DATABASE_ACTIONS_PASSWORD:-}" ]]; then
    environment_args+=(
      -e "DATABASE_ACTIONS_PASSWORD=${DATABASE_ACTIONS_PASSWORD}"
    )
  fi

  compose_base --profile e2e build playwright

  compose_base --profile e2e run --rm \
    -e "PLAYWRIGHT_OUTPUT_DIR=/tests/artifacts/output/${name}" \
    -e "PLAYWRIGHT_REPORT_DIR=/tests/artifacts/report/${name}" \
    "${environment_args[@]}" \
    playwright \
    "${playwright_command[@]}"

  info \
    "Playwright HTML report: " \
    "tests/e2e/artifacts/playwright/report/${name}/index.html"
}

assert_no_apex_files() {
  if compose_base exec -T db bash -c '
    test ! -s /opt/oracle/apex/apexins.sql &&
    test ! -s /opt/oracle/apex/apxchpwd.sql &&
    test ! -s /opt/oracle/apex/images/apex_version.txt
  '; then
    pass "APEX installation files are absent."
  else
    fail "APEX installation files exist even though INSTALL_APEX was disabled."
  fi
}

# Extract APEX version from installation files
get_apex_files_version() {
  local version
  version=$(
    compose_base exec -T ords \
      cat /opt/oracle/apex/images/apex_version.txt
  )
  [[ -n "$version" ]] || fail \
    "Unable to determine the APEX version from installation files."
  printf '%s\n' "${version##* }"
}

get_apex_version() {
  local pdb="$1"
  local version

  version="$(
    run_sys_sql get_apex_version.sql "$pdb" |
      awk 'NF { line=$0 } END { print line }' |
      xargs
  )"

  [[ -n "$version" ]] ||
    fail "Unable to determine the installed APEX version."

  printf '%s\n' "$version"
}

# Verify database APEX version matches expected version
assert_apex_version() {
  local actual expected
  expected="$1"
  actual="$(get_apex_version "$E2E_ORACLE_PDB")"
  [[ -n "$actual" ]] || fail \
    "Unable to determine the APEX version from the database."
  if is_version "$actual" "$expected"; then
    pass "Database APEX version $actual matches expected version $expected."
  else
    fail "Database APEX version mismatch: expected $expected, got $actual."
  fi
}

# Verify installation files version matches expected version
assert_apex_files_version() {
  local actual expected
  expected="$1"
  actual="$(get_apex_files_version)"
  if is_version  "$actual" "$expected"; then
    pass "APEX installation files version $actual matches expected version $expected."
  else
    fail "APEX installation files version mismatch: expected $expected, got $actual."
  fi
}

# Shared acceptance baseline for every APEX-enabled environment.
# Keep only invariants that must hold after install, upgrade, and rebuild.
assert_apex_environment() {
  local expected_version="$1"
  local rest_user

  assert_apex_version \
    "$expected_version"

  assert_apex_files_version \
    "$expected_version"

  run_sys_sql \
    assert_schema_roles.sql \
    "$E2E_ORACLE_PDB" \
    "$E2E_SCHEMA" \
    DB_DEVELOPER_ROLE \
    CLOUD_USER_ROLE

  for rest_user in "$E2E_SCHEMA" PDBADMIN; do
    run_sys_sql \
      assert_rest_enabled.sql \
      "$E2E_ORACLE_PDB" \
      "$rest_user"
  done

  run_sys_sql \
    assert_dbms_cloud.sql \
    "$E2E_ORACLE_PDB"
}

# Verify that all expected setup files were generated
assert_generated_setup_files() {
  local file
  for file in .env apex_instance_parameters.yaml apex_workspaces.yaml ssl/ca.cer ssl/server.cer ssl/server.key ssl/fullChain.cer; do
    [[ -s "$file" ]] || fail "Setup did not create a non-empty $file."
  done
}

dump_logs() {
  echo
  echo "===== docker compose ps ====="
  compose_ollama ps || true

  local service
  for service in db ords ollama nginx; do
    echo
    echo "===== $service log ====="
    compose_ollama logs --tail=300 "$service" 2>/dev/null || true
  done
}

# Record the phase before executing it so a failure leaves the exact phase
# to rerun. Persist variables only after success so resume restores the last
# known-good cross-phase state rather than partially updated failure state.
write_current_phase() {
  local function_name="$1"
  local tmp

  mkdir -p "$E2E_STATE_DIR"

  tmp="${E2E_RESUME_PHASE_FILE}.tmp"

  printf '%s\n' "$function_name" > "$tmp"
  mv "$tmp" "$E2E_RESUME_PHASE_FILE"
}

save_e2e_state() {
  local variable
  local tmp

  mkdir -p "$E2E_STATE_DIR"

  tmp="${E2E_STATE_FILE}.tmp"
  : > "$tmp"

  for variable in "${E2E_STATE_VARIABLES[@]}"; do
    if [[ -v "$variable" ]]; then
      printf '%s=%q\n' \
        "$variable" \
        "${!variable}" \
        >> "$tmp"
    fi
  done

  mv "$tmp" "$E2E_STATE_FILE"
}

load_e2e_state() {
  [[ -s "$E2E_STATE_FILE" ]] || return 0

  # shellcheck source=/dev/null
  source "$E2E_STATE_FILE"
}

clear_e2e_state() {
  rm -f \
    "$E2E_RESUME_PHASE_FILE" \
    "$E2E_STATE_FILE"
}

find_phase_index() {
  local function_name="$1"
  local i

  for i in "${!E2E_PHASE_FUNCTIONS[@]}"; do
    if [[ "${E2E_PHASE_FUNCTIONS[$i]}" == "$function_name" ]]; then
      printf '%s\n' "$i"
      return 0
    fi
  done

  return 1
}
