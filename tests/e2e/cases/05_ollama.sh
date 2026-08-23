#!/usr/bin/env bash

set -Eeuo pipefail

# Enable Ollama CPU and verify model pull
enable_ollama_cpu() {
  set_env_value .env OLLAMA_PULL_MODELS "$E2E_OLLAMA_MODEL"

  compose_ollama up -d ollama nginx
  wait_for_service_health \
    "compose_ollama" \
    "ollama" \
    "$E2E_SERVICE_TIMEOUT"

  wait_for_service_health \
    "compose_ollama" \
    "nginx" \
    "$E2E_SERVICE_TIMEOUT"

  # The model pull is a database startup script. Recreate only the database
  # container so the persisted database remains intact but startup scripts rerun.
  compose_ollama up -d --force-recreate db
  wait_for_service_health \
    "compose_ollama" \
    "db" \
    "$E2E_SERVICE_TIMEOUT"
  wait_for_model \
    "$E2E_OLLAMA_MODEL" \
    "$E2E_MODEL_TIMEOUT"
  wait_for_service_health \
    "compose_ollama" \
    "ords" \
    "$E2E_SERVICE_TIMEOUT"
}
register_phase \
  "Enable Ollama CPU" \
  "enable_ollama_cpu"


verify_database_gateway_access() {
  run_schema_sql_ollama assert_gateway.sql "$E2E_OLLAMA_MODEL"
}
register_phase \
  "Verify database access to Ollama through HTTPS gateway" \
  "verify_database_gateway_access"