#!/usr/bin/env bash

set -Eeuo pipefail

prepare_clean_e2e_environment() {

  # Clean environment and prepare for testing
  compose_ollama down -v --remove-orphans || true

  rm -f .env apex_instance_parameters.yaml apex_workspaces.yaml
  rm -rf ssl tests/e2e/artifacts/playwright

  mkdir -p \
    tests/e2e/artifacts/playwright/output/initial \
    tests/e2e/artifacts/playwright/report/initial \
    tests/e2e/artifacts/playwright/output/rebuild \
    tests/e2e/artifacts/playwright/report/rebuild \
    tests/e2e/artifacts/playwright/output/no-apex \
    tests/e2e/artifacts/playwright/report/no-apex \
    tests/e2e/artifacts/playwright/output/earlier-apex \
    tests/e2e/artifacts/playwright/report/earlier-apex \
    tests/e2e/artifacts/playwright/output/upgraded-apex \
    tests/e2e/artifacts/playwright/report/upgraded-apex

  pass "Clean E2E environment prepared."
}
register_phase \
  "Prepare clean E2E environment" \
  "prepare_clean_e2e_environment"

run_repository_lint_checks() {
  ./tests/lint/run.sh
  pass "Repository lint checks passed."
}
register_phase \
  "Run repository lint checks" \
  "run_repository_lint_checks"