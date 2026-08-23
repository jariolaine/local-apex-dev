#!/usr/bin/env bash

set -Eeuo pipefail

# E2E phases for running Database and ORDS without APEX.
# This file is sourced by tests/e2e/run.sh after lib/common.sh is loaded.

# INSTALL_APEX=N skips only the APEX distribution. Configuration and TLS files
# must still be generated so APEX can be enabled later on the same database.
prepare_environment_without_apex() {
  run_setup -e INSTALL_APEX=N
  assert_generated_setup_files
  pass \
    "Setup completed with APEX installation disabled."
}
register_phase \
  "Prepare environment without APEX" \
  "prepare_environment_without_apex"


configure_test_environment() {
  apply_test_environment
  pass \
    "E2E credentials and host bindings configured."
}
register_phase \
  "Configure E2E credentials and host bindings" \
  "configure_test_environment"


start_services_without_apex() {
  start_base_services
}
register_phase \
  "Start Database and ORDS without APEX" \
  "start_services_without_apex"


verify_environment_without_apex() {
  assert_no_apex_files
  run_sys_sql \
    "assert_no_apex.sql" \
    "$E2E_ORACLE_PDB" \
    "$E2E_SCHEMA"

  run_sys_sql \
    "assert_dbms_cloud.sql" \
    "$E2E_ORACLE_PDB"

  run_sys_sql \
    "assert_rest_enabled.sql" \
    "$E2E_ORACLE_PDB" \
    "PDBADMIN"

  pass \
    "Database, ORDS, and DBMS_CLOUD operate correctly without APEX."
}
register_phase \
  "Verify environment without APEX" \
  "verify_environment_without_apex"

verify_database_actions_without_apex() {
  DATABASE_ACTIONS_USER="PDBADMIN" \
  DATABASE_ACTIONS_PASSWORD="$E2E_ORACLE_PWD" \
    run_playwright \
      "no-apex" \
      database-actions.spec.ts

  pass \
    "Oracle Database Actions login succeeded as PDBADMIN without APEX installed."
}
register_phase \
  "Verify Database Actions without APEX" \
  "verify_database_actions_without_apex"
