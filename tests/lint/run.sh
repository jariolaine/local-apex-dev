#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="$(git rev-parse --show-toplevel)"
LINT_IMAGE="local-apex-dev-lint:latest"

cd "${PROJECT_DIR}"

echo "🔍  Running lint checks..."

# ==============================================================================
# Check staged files
# ==============================================================================

echo "➡️  Checking staged files..."

# Detect whitespace errors in staged changes.
git diff --cached --check

# Prevent generated configuration, credentials, certificates, dependencies,
# and test artifacts from being committed accidentally.
FORBIDDEN_FILES=()

while IFS= read -r -d '' file; do
  case "${file}" in
    .env | */.env)
      FORBIDDEN_FILES+=("${file}")
      ;;

    apex_instance_parameters.yaml | apex_workspaces.yaml)
      FORBIDDEN_FILES+=("${file}")
      ;;

    ssl/*)
      FORBIDDEN_FILES+=("${file}")
      ;;

    tests/e2e/artifacts/*)
      FORBIDDEN_FILES+=("${file}")
      ;;

    */node_modules/*)
      FORBIDDEN_FILES+=("${file}")
      ;;
  esac
done < <(
  git diff \
    --cached \
    --name-only \
    --diff-filter=ACMR \
    -z
)

if (( ${#FORBIDDEN_FILES[@]} > 0 )); then
  echo "❌  Generated or sensitive files are staged:"
  printf '   %s\n' "${FORBIDDEN_FILES[@]}"
  echo
  echo "Remove them from the Git index before committing."
  exit 1
fi

# ==============================================================================
# Check Docker
# ==============================================================================

if ! command -v docker >/dev/null 2>&1; then
  echo "❌  Docker is required to run lint checks."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "❌  Docker is installed, but the Docker daemon is not available."
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "❌  Docker Compose is required to run lint checks."
  exit 1
fi

# ==============================================================================
# Build lint environment
# ==============================================================================

echo "➡️  Preparing lint container..."

docker build \
  --quiet \
  --tag "${LINT_IMAGE}" \
  tests/lint \
  >/dev/null

# shellcheck disable=SC2016
run_lint() {
  local command="$1"

  docker run \
    --rm \
    --network none \
    --volume "${PROJECT_DIR}:/repo:ro" \
    --workdir /repo \
    "${LINT_IMAGE}" \
    -lc "${command}"
}

# ==============================================================================
# Check Bash syntax
# ==============================================================================

echo "➡️  Checking Bash syntax..."

# shellcheck disable=SC2016
run_lint '
  set -Eeuo pipefail

  mapfile -d "" -t files < <(
    git ls-files -zco --exclude-standard -- "*.sh"
  )

  echo "    • Checking syntax of ${#files[@]} shell scripts..."

  for file in "${files[@]}"; do
    bash -n "${file}"
  done
'

# ==============================================================================
# Run ShellCheck
# ==============================================================================

echo "➡️  Running ShellCheck..."

# shellcheck disable=SC2016
run_lint '
  set -Eeuo pipefail

  mapfile -d "" -t files < <(
    git ls-files -zco --exclude-standard -- "*.sh"
  )

  echo "    • Linting ${#files[@]} shell scripts..."

  if (( ${#files[@]} > 0 )); then
    shellcheck "${files[@]}"
  fi
'

# ==============================================================================
# SQL linting
# ==============================================================================

echo "➡️  Running SQLFluff..."

# shellcheck disable=SC2016
run_lint '
  set -Eeuo pipefail

  mapfile -d "" -t files < <(
    git ls-files -zco --exclude-standard -- "*.sql"
  )

  echo "    • Linting ${#files[@]} SQL files..."

  if (( ${#files[@]} > 0 )); then
    sqlfluff lint "${files[@]}"
  fi
'

# ==============================================================================
# Run yamllint
# ==============================================================================

echo "➡️  Running yamllint..."

# shellcheck disable=SC2016
run_lint '
  set -Eeuo pipefail

  mapfile -d "" -t files < <(
    git ls-files -zco --exclude-standard -- "*.yml" "*.yaml"
  )

  echo "    • Linting ${#files[@]} YAML files..."

  if (( ${#files[@]} > 0 )); then
    yamllint \
      -d "{extends: relaxed, rules: {line-length: disable}}" \
      "${files[@]}"
  fi
'

# ==============================================================================
# Run markdownlint
# ==============================================================================

echo "➡️  Running markdownlint..."

# shellcheck disable=SC2016
run_lint '
  set -Eeuo pipefail

  mapfile -d "" -t files < <(
    git ls-files -zco --exclude-standard -- "*.md"
  )

  echo "    • Linting ${#files[@]} Markdown files..."

  if (( ${#files[@]} > 0 )); then
    markdownlint-cli2 "${files[@]}"
  fi
'

# ==============================================================================
# Validate Playwright tests and helper
# ==============================================================================
echo "➡️  Validating Playwright tests..."

docker build \
  --quiet \
  --tag local-apex-dev-playwright-check:latest \
  tests/e2e/ui \
  >/dev/null

# ==============================================================================
# Validate GitHub Actions workflows
# ==============================================================================

if [[ -d ".github/workflows" ]]; then
  echo "➡️  Running actionlint..."

  # shellcheck disable=SC2016
  run_lint '
    set -Eeuo pipefail
    actionlint -color
  '
fi

# ==============================================================================
# Validate Docker Compose configurations
# ==============================================================================

echo "➡️  Validating Docker Compose configurations..."

compose_config_check() {
  local description="$1"
  shift

  echo "    • ${description}"

  docker compose \
    --env-file templates/env.template \
    "$@" \
    config \
    --quiet
}

# ------------------------------------------------------------------------------
# Base environment
# ------------------------------------------------------------------------------

compose_config_check \
  "Database + ORDS" \
  -f docker-compose.yml

# ------------------------------------------------------------------------------
# APEX
# ------------------------------------------------------------------------------

if [[ -f compose/apex.yml ]]; then
  compose_config_check \
    "Database + ORDS + APEX" \
    -f docker-compose.yml \
    -f compose/apex.yml
fi

# ------------------------------------------------------------------------------
# Ollama CPU
# ------------------------------------------------------------------------------

if [[ -f compose/ollama.yml ]]; then
  compose_config_check \
    "Database + ORDS + Ollama CPU" \
    -f docker-compose.yml \
    -f compose/ollama.yml
fi

# ------------------------------------------------------------------------------
# Ollama NVIDIA GPU
# ------------------------------------------------------------------------------

if [[ \
  -f compose/ollama.yml &&
  -f compose/ollama.cuda.yml
]]; then
  compose_config_check \
    "Database + ORDS + Ollama NVIDIA GPU" \
    -f docker-compose.yml \
    -f compose/ollama.yml \
    -f compose/ollama.cuda.yml
fi

# ------------------------------------------------------------------------------
# Playwright E2E environment
# ------------------------------------------------------------------------------

if [[ -f tests/e2e/compose.yml ]]; then
  E2E_COMPOSE_FILES=(
    -f docker-compose.yml
  )

  if [[ -f compose/apex.yml ]]; then
    E2E_COMPOSE_FILES+=(
      -f compose/apex.yml
    )
  fi

  E2E_COMPOSE_FILES+=(
    -f tests/e2e/compose.yml
  )

  E2E_APEX_ADMIN_PASSWORD='Test#123' \
  E2E_APEX_WORKSPACE_PASSWORD='Test#123' \
  E2E_SCHEMA_PASSWORD='Test#123' \
    compose_config_check \
      "Playwright E2E environment" \
      "${E2E_COMPOSE_FILES[@]}"
fi

# ==============================================================================
# Validate lint Compose file, if present
# ==============================================================================

if [[ -f tests/lint/compose.yml ]]; then
  echo "    • Lint environment"

  docker compose \
    -f tests/lint/compose.yml \
    config \
    --quiet
fi

echo
echo "✅  All checks passed."