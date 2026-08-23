#!/usr/bin/env bash

set -Eeuo pipefail

# E2E phases for installing an earlier APEX release and upgrading it to
# the latest available release on the same database volume.

prepare_earlier_apex_files() {
  # Stop containers but preserve the database volume. This verifies that APEX
  # can be enabled later on a database initially started without APEX.
  compose_base down

  run_setup -e APEX_DOWNLOAD_URL="$E2E_OLD_APEX_URL"

  assert_generated_setup_files

  pass \
    "APEX ${E2E_OLD_APEX_VERSION} installation files prepared."
}
register_phase \
  "Prepare APEX ${E2E_OLD_APEX_VERSION} installation files" \
  "prepare_earlier_apex_files"


start_services_with_earlier_apex() {
  start_base_services
}
register_phase \
  "Install APEX ${E2E_OLD_APEX_VERSION} in the existing database" \
  "start_services_with_earlier_apex"


verify_earlier_apex_installation() {
  # Capture the installed version before upgrading so the test proves that
  # an actual version transition occurred.
  E2E_OLD_APEX_DB_VERSION="$(
    get_apex_version "$E2E_ORACLE_PDB"
  )"

  assert_apex_environment \
    "$E2E_OLD_APEX_VERSION"

  run_schema_sql \
    assert_no_persistence.sql \
    "$E2E_ORACLE_PDB" \
    "$E2E_SCHEMA"

  pass \
    "APEX ${E2E_OLD_APEX_VERSION} installation is valid " \
    "and ready for upgrade testing."

}
register_phase \
  "Verify APEX ${E2E_OLD_APEX_VERSION} installation" \
  "verify_earlier_apex_installation"


create_pre_upgrade_persistence_data() {
  run_schema_sql \
    create_persistence.sql \
    "$E2E_ORACLE_PDB" \
    "$E2E_SCHEMA"
}
register_phase \
  "Create pre-upgrade persistence data" \
  "create_pre_upgrade_persistence_data"


verify_earlier_apex_browser_logins() {
  run_playwright "earlier-apex"
  pass \
    "APEX Administration, workspace, and Database Actions browser checks " \
    "passed on APEX ${E2E_OLD_APEX_VERSION}."
}
register_phase \
  "Verify browser logins on APEX ${E2E_OLD_APEX_VERSION}" \
  "verify_earlier_apex_browser_logins"


prepare_latest_apex_files_for_upgrade() {
  # Preserve the database volume so startup performs an in-place APEX upgrade
  # rather than installing into a new database.
  compose_base down

  run_setup
  assert_generated_setup_files

  pass \
    "Latest APEX installation files prepared for upgrade."
}
register_phase \
  "Prepare latest APEX installation files for upgrade" \
  "prepare_latest_apex_files_for_upgrade"


start_services_for_apex_upgrade() {
  start_base_services
}
register_phase \
  "Upgrade APEX in the existing database" \
  "start_services_for_apex_upgrade"


verify_apex_upgrade() {
  local latest_apex_version
  local new_apex_db_version

  latest_apex_version="$(
    get_apex_files_version
  )"

  new_apex_db_version="$(
    get_apex_version "$E2E_ORACLE_PDB"
  )"

  [[ -n "${E2E_OLD_APEX_DB_VERSION:-}" ]] ||
    fail "Earlier APEX database version is unavailable."

  [[ "$new_apex_db_version" != "$E2E_OLD_APEX_DB_VERSION" ]] ||
    fail "APEX version did not change during upgrade:" \
      "${E2E_OLD_APEX_DB_VERSION}."

  assert_apex_environment \
    "$latest_apex_version"

  pass \
    "APEX upgraded from ${E2E_OLD_APEX_DB_VERSION} " \
    "to ${new_apex_db_version}."
}
register_phase \
  "Verify APEX upgrade" \
  "verify_apex_upgrade"


verify_post_upgrade_persistence() {
  run_schema_sql assert_persistence.sql
}
register_phase \
  "Verify data persisted through APEX upgrade" \
  "verify_post_upgrade_persistence"


verify_upgraded_apex_browser_logins() {
  run_playwright "upgraded-apex"
  pass \
    "APEX Administration, workspace, and Database Actions browser checks " \
    "passed after upgrade."
}
register_phase \
  "Verify browser logins after APEX upgrade" \
  "verify_upgraded_apex_browser_logins"