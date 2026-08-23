#!/usr/bin/env bash

set -Eeuo pipefail

# Destructive volume reset test
destructive_volume_reset() {
  compose_ollama down -v --remove-orphans
  pass "Persistent Docker volumes were removed."
}
register_phase \
  "Destructive volume reset" \
  "destructive_volume_reset"


# Rebuild from destroyed volumes test
prepare_environment_for_rebuild() {
  run_setup \
    -e RESET_CONFIGURATION_FILES=Y \
    -e ROTATE_CERTIFICATES=Y
}
register_phase \
  "Prepare environment for rebuild" \
  "prepare_environment_for_rebuild"


configure_test_for_rebuild() {
  apply_test_environment
  pass \
    "E2E credentials and host bindings configured."
}
register_phase \
  "Configure E2E credentials and host bindings" \
  "configure_test_for_rebuild"


start_services_for_rebuild() {
  start_base_services
}
register_phase \
  "Start Database and ORDS for rebuild" \
  "start_services_for_rebuild"


verify_environment_rebuild() {
  local latest_apex_version

  latest_apex_version="$(
    get_apex_files_version
  )"

  assert_apex_environment \
    "$latest_apex_version"

  run_schema_sql \
    assert_no_persistence.sql \
    "$E2E_ORACLE_PDB" \
    "$E2E_SCHEMA"

  pass \
    "Database, ORDS, APEX, REST enablement, and DBMS_CLOUD" \
    "checks passed after rebuild."
}
register_phase \
  "Verify rebuilt database environment" \
  "verify_environment_rebuild"


verify_rebuilt_browser_access() {
  run_playwright "rebuild"

  pass \
    "Browser checks passed after destructive rebuild."
}
register_phase \
  "Verify browser access after rebuild" \
  "verify_rebuilt_browser_access"