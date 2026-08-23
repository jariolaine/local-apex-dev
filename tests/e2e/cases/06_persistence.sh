#!/usr/bin/env bash

set -Eeuo pipefail

# Verify persistence across stop and restart
create_restart_persistence_data() {
  run_schema_sql_ollama \
    assert_no_persistence.sql \
    "$E2E_ORACLE_PDB" \
    "$E2E_SCHEMA"

  run_schema_sql_ollama \
    create_persistence.sql \
    "$E2E_ORACLE_PDB" \
    "$E2E_SCHEMA"
}
register_phase \
  "Create persistence data before restart" \
  "create_restart_persistence_data"

restart_ollama_environment() {
  compose_ollama down

  compose_ollama up -d \
    db \
    ords \
    ollama \
    nginx

  wait_for_services \
    compose_ollama \
    "$E2E_SERVICE_TIMEOUT" \
    ollama \
    nginx \
    db \
    ords
}
register_phase \
  "Restart complete environment" \
  "restart_ollama_environment"

verify_persistence_after_restart() {
  run_schema_sql_ollama \
    "assert_gateway.sql" \
    "$E2E_OLLAMA_MODEL"

  run_schema_sql_ollama \
    "assert_persistence.sql"
}
register_phase \
  "Verify persistence after restart" \
  "verify_persistence_after_restart"

# Verify idempotent setup rerun
verify_idempotent_setup() {
  local before_hash
  local after_hash

  compose_ollama down

  before_hash="$(
    generated_files_checksums
  )"

  run_setup

  after_hash="$(
    generated_files_checksums
  )"

  [[ "$before_hash" == "$after_hash" ]] ||
    fail \
      "Normal setup rerun changed preserved configuration or certificates."

  pass \
    "Normal setup rerun preserved existing configuration and valid certificates."
}
register_phase \
  "Verify idempotent setup rerun" \
  "verify_idempotent_setup"

# Verify configuration reset functionality
verify_configuration_reset() {
  local cert_hash_before
  local cert_hash_after
  local file
  printf '\n# E2E_RESET_SENTINEL\n' >> .env
  printf '\n# E2E_RESET_SENTINEL\n' >> apex_instance_parameters.yaml
  printf '\n# E2E_RESET_SENTINEL\n' >> apex_workspaces.yaml

  cert_hash_before="$(checksum_file ssl/ca.cer)"
  run_setup -e RESET_CONFIGURATION_FILES=Y

  for file in .env apex_instance_parameters.yaml apex_workspaces.yaml; do
    if grep -q 'E2E_RESET_SENTINEL' "$file"; then
      fail "RESET_CONFIGURATION_FILES did not regenerate $file."
    fi
  done

  cert_hash_after="$(checksum_file ssl/ca.cer)"
  [[ "$cert_hash_before" == "$cert_hash_after" ]] || fail \
    "Configuration reset unexpectedly rotated the local CA certificate."
  apply_test_environment
  pass "Configuration reset regenerated configuration without rotating valid certificates."
}
register_phase \
  "Verify configuration reset" \
  "verify_configuration_reset"