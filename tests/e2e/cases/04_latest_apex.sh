#!/usr/bin/env bash

set -Eeuo pipefail

#Clean installation of latest APEX version

prepare_latest_apex_files() {
  compose_base down -v --remove-orphans
  rm -f .env apex_instance_parameters.yaml apex_workspaces.yaml
  rm -rf ssl
  run_setup
  assert_generated_setup_files
  pass \
    "APEX latest installation files prepared."
}
register_phase \
  "Prepare APEX latest installation files" \
  "prepare_latest_apex_files"


configure_latest_apex_test_environment() {
  apply_test_environment
  pass \
    "E2E credentials and host bindings configured."
}
register_phase \
  "Configure E2E credentials and host bindings" \
  "configure_latest_apex_test_environment"


start_services_with_latest_apex() {
  start_base_services
}
register_phase \
  "Install latest APEX in the clean database" \
  "start_services_with_latest_apex"


verify_latest_apex_installation() {
  local latest_apex_version

  latest_apex_version="$(
    get_apex_files_version
  )"

  assert_apex_environment \
    "$latest_apex_version"
}
register_phase \
  "Verify latest APEX installation" \
  "verify_latest_apex_installation"

# Verify APEX browser logins for latest version
verify_latest_apex_browser_logins() {
  run_playwright "initial"
  pass \
    "APEX Administration, workspace, and Database Actions browser checks " \
    "passed on latest APEX."
}
register_phase \
  "Verify browser logins on latest APEX" \
  "verify_latest_apex_browser_logins"
