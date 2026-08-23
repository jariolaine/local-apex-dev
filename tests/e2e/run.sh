#!/usr/bin/env bash

# Main E2E acceptance-test runner.
#
# Numbered case files under tests/e2e/cases are sourced in lexical order.
# Each case registers one or more phase functions. The runner derives the
# total phase count from those registrations and executes them sequentially.
#
# Registered phase functions are resume checkpoints and should be safe to
# execute again from their beginning after a previous failure.

set -Eeuo pipefail

# Set up script and repository paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "$REPO_ROOT"

E2E_PHASE=0
E2E_PHASE_TOTAL=0
E2E_LOG_FILE="${E2E_LOG_FILE:-${SCRIPT_DIR}/artifacts/e2e.log}"

# Test configuration constants
E2E_ORACLE_PDB="FREEPDB1"
E2E_APEX_ADMIN_USER="ADMIN"
E2E_APEX_WORKSPACE="SANDBOX"
E2E_APEX_WORKSPACE_USER="ADMIN"
E2E_SCHEMA="WKSP_SANDBOX"

# Resume configuration
E2E_RESUME="${E2E_RESUME:-N}"
E2E_STATE_DIR="${SCRIPT_DIR}/artifacts/state"
E2E_RESUME_PHASE_FILE="${E2E_STATE_DIR}/current-phase"
E2E_STATE_FILE="${E2E_STATE_DIR}/variables.sh"

# This suite intentionally deletes its generated configuration and Docker volumes.
# Explicit opt-in is required.
# Test environment configuration with defaults
E2E_ORACLE_PWD="${E2E_ORACLE_PWD:-E2eOracle#26ai}"

E2E_ALLOW_DESTRUCTIVE="${E2E_ALLOW_DESTRUCTIVE:-N}"         # Requires explicit opt-in to delete config/volumes
E2E_KEEP_RUNNING="${E2E_KEEP_RUNNING:-N}"                   # Keep containers running after test completion
E2E_PROJECT_NAME="${E2E_PROJECT_NAME:-local-apex-dev-e2e}"  # Docker project name

# Ollama and networking configuration
E2E_OLLAMA_MODEL="${E2E_OLLAMA_MODEL:-all-minilm:22m}"
E2E_DB_HOST_BINDING="${E2E_DB_HOST_BINDING:-127.0.0.1:11521}"
E2E_ORDS_HOST_BINDING="${E2E_ORDS_HOST_BINDING:-127.0.0.1:18181}"

# Timeout values for services
E2E_SERVICE_TIMEOUT="${E2E_SERVICE_TIMEOUT:-1800}"
E2E_MODEL_TIMEOUT="${E2E_MODEL_TIMEOUT:-1800}"

# APEX version configuration
E2E_OLD_APEX_VERSION="${E2E_OLD_APEX_VERSION:-24.2}" # Version to test upgrade from

# APEX download URL for older version
E2E_OLD_APEX_URL="${E2E_OLD_APEX_URL:-https://download.oracle.com/otn_software/apex/apex_${E2E_OLD_APEX_VERSION}_en.zip}"

# Export environment variables for use in containers
export E2E_APEX_ADMIN_PASSWORD="$E2E_ORACLE_PWD"
export E2E_APEX_WORKSPACE_PASSWORD="$E2E_ORACLE_PWD"
export E2E_SCHEMA_PASSWORD="$E2E_ORACLE_PWD"
export E2E_APEX_ADMIN_USER \
  E2E_APEX_WORKSPACE \
  E2E_APEX_WORKSPACE_USER \
  E2E_SCHEMA E2E_ORACLE_PDB

# Source helper functions from the common.sh file
# shellcheck source=tests/e2e/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Require explicit opt-in for destructive operations
is_true "$E2E_ALLOW_DESTRUCTIVE" || {
  cat >&2 <<'MSG'
ERROR : This test intentionally deletes generated configuration, certificates,
        and Docker volumes for its E2E project.

Run explicitly with:
  E2E_ALLOW_DESTRUCTIVE=Y ./tests/e2e/run.sh
MSG
  exit 1
}

initialize_e2e_logging

if ! is_true "$E2E_RESUME"; then
  clear_e2e_state
fi

# Setup host identity arguments for Linux systems to maintain correct file ownership
if [[ "$(uname -s)" == "Linux" ]]; then

  export HOST_UID="${HOST_UID:-$(id -u)}"
  export HOST_GID="${HOST_GID:-$(id -g)}"

  setup_host_identity_args=(
    -e "HOST_UID=${HOST_UID}"
    -e "HOST_GID=${HOST_GID}"
  )
fi

# Verify required tools are available
command -v docker >/dev/null 2>&1 || fail "docker was not found."
docker compose version >/dev/null 2>&1 || fail "docker compose is not available."

# Build base Docker Compose file list with project configuration
BASE_COMPOSE_FILES=(-f docker-compose.yml)
if [[ -f compose/apex.yml ]]; then
  BASE_COMPOSE_FILES+=(-f compose/apex.yml)
fi
BASE_COMPOSE_FILES+=(-f tests/e2e/compose.yml)

# Add Ollama-specific compose files for later use
OLLAMA_COMPOSE_FILES=("${BASE_COMPOSE_FILES[@]}" -f compose/ollama.yml)

# Check for conflicting containers to prevent interference with test environment.
# Fixed container_name values in the project mean an E2E project can still
# collide with a normal development stack. Refuse to touch foreign containers.
for name in db-26ai-free ords-node-1 ollama-llm ollama-api-gateway local-apex-dev-setup; do
  if docker inspect "$name" >/dev/null 2>&1; then
    owner="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$name" 2>/dev/null || true)"
    if [[ "$owner" != "$E2E_PROJECT_NAME" ]]; then
      fail "Container $name belongs to Compose project '$owner'. Stop the normal development environment before running E2E tests."
    fi
  fi
done

trap on_exit EXIT

readonly E2E_CASES_DIR="${SCRIPT_DIR}/cases"

shopt -s nullglob
case_files=("${E2E_CASES_DIR}"/*.sh)
shopt -u nullglob

if (( ${#case_files[@]} == 0 )); then
  fail "No E2E test cases found in ${E2E_CASES_DIR}."
fi

for case_file in "${case_files[@]}"; do
  # shellcheck source=/dev/null
  source "$case_file"
done

E2E_PHASE_TOTAL="${#E2E_PHASE_FUNCTIONS[@]}"
E2E_START_INDEX=0

if is_true "$E2E_RESUME"; then
  [[ -s "$E2E_RESUME_PHASE_FILE" ]] ||
    fail "No failed E2E phase is available to resume."

  E2E_RESUME_PHASE="$(
    < "$E2E_RESUME_PHASE_FILE"
  )"

  load_e2e_state

  if ! E2E_START_INDEX="$(
    find_phase_index "$E2E_RESUME_PHASE"
  )"; then
    fail \
      "Saved E2E phase is no longer registered: ${E2E_RESUME_PHASE}"
  fi

  # phase() increments E2E_PHASE before displaying it.
  E2E_PHASE="$E2E_START_INDEX"

  info \
    "Resuming from phase $((E2E_START_INDEX + 1))/${E2E_PHASE_TOTAL}:" \
    "${E2E_PHASE_NAMES[$E2E_START_INDEX]}"

fi

for ((i = E2E_START_INDEX; i < E2E_PHASE_TOTAL; i++)); do
  phase_name="${E2E_PHASE_NAMES[$i]}"
  phase_function="${E2E_PHASE_FUNCTIONS[$i]}"

  write_current_phase "$phase_function"

  phase "$phase_name"

  "$phase_function"

  save_e2e_state
done

clear_e2e_state

if ! is_true "$E2E_KEEP_RUNNING"; then
  compose_ollama down -v --remove-orphans
fi

trap - EXIT
printf '\nPASS : All %d end-to-end acceptance phases completed successfully.\n' "$E2E_PHASE_TOTAL"
info "E2E log: ${E2E_LOG_FILE}"