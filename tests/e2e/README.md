# End-to-End Acceptance Tests

The end-to-end (E2E) suite exercises the complete `local-apex-dev` lifecycle
against real Docker containers.

It validates:

- Oracle Database Free and ORDS startup.
- Running Database and ORDS without APEX.
- Installing APEX later into an existing database.
- Upgrading an earlier APEX release to the latest downloaded release.
- Clean latest-APEX installation.
- APEX Administration Services and workspace browser access.
- Oracle Database Actions browser access.
- REST-enabled database schemas.
- DBMS_CLOUD package validity.
- Ollama and the internal HTTPS gateway.
- Database persistence across container restarts.
- Idempotent setup reruns.
- Configuration reset behavior.
- TLS certificate preservation and rotation behavior.
- Destructive volume removal and full rebuild.

The suite also runs the repository lint checks before the main acceptance
scenarios.

## Warning: destructive test suite

The suite is intentionally destructive.

A fresh run removes generated project configuration, local TLS certificates,
Playwright artifacts, and Docker volumes belonging to the E2E Compose project.
Later phases deliberately remove persistent Docker volumes again to verify that
the environment can be rebuilt from scratch.

The runner refuses to start unless destructive execution is explicitly enabled:

```bash
E2E_ALLOW_DESTRUCTIVE=Y ./tests/e2e/run.sh
```

The E2E project uses isolated host port bindings and its own Docker Compose
project name. The runner also checks the project's fixed container names and
refuses to continue if those containers belong to another Compose project.

Do not run the suite while the normal development environment is using the same
fixed container names.

## Prerequisites

The host needs:

- Git.
- Bash 4 or newer.
- Docker Engine or Docker Desktop.
- Docker Compose v2 (`docker compose`).
- Network access to pull images, download APEX releases, install the
  Playwright dependency while building the test image, and download the
  configured Ollama model.

Node.js, npm, Playwright, ShellCheck, SQLFluff, yamllint, markdownlint, and
actionlint do not need to be installed directly on the host.

On Linux, the runner passes the host UID and GID where needed so generated
files and Playwright artifacts have appropriate ownership.

## Run the complete suite

Run from the repository root:

```bash
E2E_ALLOW_DESTRUCTIVE=Y ./tests/e2e/run.sh
```

The runner discovers numbered case files under `tests/e2e/cases/`, registers
their phase functions in lexical order, calculates the total phase count
dynamically, and executes the phases sequentially.

The suite does not use a manually maintained phase count.

## Default E2E configuration

The suite intentionally uses fixed fixture identities for the main Oracle and
APEX objects.

| Setting | Default |
| --- | --- |
| Oracle PDB | `FREEPDB1` |
| APEX instance administrator | `ADMIN` |
| APEX workspace | `SANDBOX` |
| APEX workspace user | `ADMIN` |
| Workspace schema | `WKSP_SANDBOX` |
| Earlier APEX upgrade source | `24.2` |
| Ollama model | `all-minilm:22m` |
| Database host binding | `127.0.0.1:11521` |
| ORDS host binding | `127.0.0.1:18181` |
| Compose project | `local-apex-dev-e2e` |

The workspace, schema, PDB, and APEX fixture identities are fixed so the
acceptance suite validates the project's shipped example configuration rather
than maintaining a second configurable provisioning system.

## Runtime overrides

Useful overrides are:

| Variable | Purpose | Default |
| --- | --- | --- |
| `E2E_ORACLE_PWD` | Database and generated APEX test password | `E2eOracle#26ai` |
| `E2E_OLLAMA_MODEL` | Ollama model used by integration tests | `all-minilm:22m` |
| `E2E_DB_HOST_BINDING` | Database host binding | `127.0.0.1:11521` |
| `E2E_ORDS_HOST_BINDING` | ORDS host binding | `127.0.0.1:18181` |
| `E2E_SERVICE_TIMEOUT` | Service health timeout in seconds | `1800` |
| `E2E_MODEL_TIMEOUT` | Ollama model download timeout in seconds | `1800` |
| `E2E_PROJECT_NAME` | Docker Compose project name | `local-apex-dev-e2e` |
| `E2E_KEEP_RUNNING` | Keep the final rebuilt environment running | `N` |
| `E2E_RESUME` | Resume from the previously failed phase | `N` |
| `E2E_OLD_APEX_VERSION` | Earlier APEX version used by the upgrade test | `24.2` |
| `E2E_OLD_APEX_URL` | Download URL for the earlier APEX release | derived |

Example:

```bash
E2E_ALLOW_DESTRUCTIVE=Y \
E2E_ORACLE_PWD='YourStrongPassword1#' \
E2E_OLLAMA_MODEL=all-minilm:22m \
./tests/e2e/run.sh
```

The Playwright Compose layer also supports the APEX path and success-text
overrides declared in `tests/e2e/compose.yml`.

## Cleanup behavior

By default, a successful run removes the E2E containers, persistent volumes,
and orphaned containers.

To keep the final rebuilt Database and ORDS environment running:

```bash
E2E_ALLOW_DESTRUCTIVE=Y \
E2E_KEEP_RUNNING=Y \
./tests/e2e/run.sh
```

A failed run is intentionally left in place so logs, database state, browser
artifacts, and resume state can be inspected.

## Resume a failed run

Before each registered phase runs, the runner records its function name. After
a phase completes successfully, the runner persists the small amount of
cross-phase state that later phases need.

Resume metadata is stored under:

```text
tests/e2e/artifacts/state/
├── current-phase
└── variables.sh
```

After fixing a failed test, resume with:

```bash
E2E_ALLOW_DESTRUCTIVE=Y \
E2E_RESUME=Y \
./tests/e2e/run.sh
```

The runner:

1. Loads the saved cross-phase state.
2. Reads the failed phase function from `current-phase`.
3. Finds that function in the newly registered phase list.
4. Skips earlier phases.
5. Reruns the failed phase from its beginning.
6. Continues with the remaining phases.

Credentials and normal runner configuration are not saved. Reuse the same
runtime overrides when resuming that were used for the original run.

### Resume design rule

A registered phase function is a resume checkpoint.

Every phase should therefore be safe to execute again from its beginning after
a previous failure.

Phase function names are persisted as resume identifiers. Keep them unique and
stable when possible.

## Test layout

```text
tests/e2e/
├── run.sh
├── compose.yml
├── README.md
├── cases/
│   ├── 01_start.sh
│   ├── 02_no_apex.sh
│   ├── 03_earlier_apex.sh
│   ├── 04_latest_apex.sh
│   ├── 05_ollama.sh
│   ├── 06_persistence.sh
│   └── 07_rebuild.sh
├── lib/
│   └── common.sh
├── sql/
│   ├── assert_dbms_cloud.sql
│   ├── assert_gateway.sql
│   ├── assert_no_apex.sql
│   ├── assert_no_persistence.sql
│   ├── assert_persistence.sql
│   ├── assert_rest_enabled.sql
│   ├── assert_schema_roles.sql
│   ├── create_persistence.sql
│   └── get_apex_version.sql
└── ui/
    ├── Dockerfile
    ├── package.json
    ├── playwright.config.ts
    ├── helpers.ts
    ├── apex-admin.spec.ts
    ├── apex-workspace.spec.ts
    └── database-actions.spec.ts
```

## Runner architecture

### `run.sh`

The main runner:

- Defines E2E constants and runtime defaults.
- Validates destructive opt-in and required Docker tooling.
- Builds the Compose file lists.
- Protects against collisions with containers belonging to another project.
- Sources the common library.
- Discovers and sources numbered case files.
- Calculates the phase count.
- Loads resume state when requested.
- Executes registered phases.
- Cleans up after success unless `E2E_KEEP_RUNNING=Y`.

Scenario-specific acceptance logic belongs in `tests/e2e/cases/`.

### `lib/common.sh`

The common library contains reusable E2E infrastructure:

- Phase registration and progress output.
- Docker Compose wrapper functions.
- Setup execution.
- Service health waiting.
- Ollama model waiting.
- Test `.env` updates.
- Generated-file checksum helpers.
- SQL*Plus execution helpers.
- APEX version assertions.
- Shared APEX environment assertions.
- Playwright execution.
- Failure log collection.
- Resume-state persistence and lookup.

### `cases/`

Each numbered file describes one acceptance scenario.

Files are sourced in lexical order. A case defines phase functions and
registers them with:

```bash
register_phase \
  "Human-readable phase name" \
  "stable_phase_function"
```

Only the main runner calls `phase()`. Case functions must not increment the
phase counter themselves.

### `sql/`

SQL files contain database-side assertions and fixtures. They are executed
inside the Oracle Database container through the common SQL runner functions.

The scripts intentionally include SQL*Plus/SQLcl directives such as
`WHENEVER`, `SET`, and `DEFINE`. Unsupported client directives use targeted
SQLFluff `-- noqa: PRS` annotations.

Some scripts repeat SQLcl display settings after `ALTER SESSION`. This is
intentional because the session change can affect terminal output behavior in
the tested execution environment.

### `ui/`

Playwright runs entirely in Docker.

During image build:

```text
npx playwright test --list
```

parses and registers all specs so syntax errors and broken local imports are
detected before expensive browser phases.

## Acceptance scenarios

### 1. Repository and environment preparation

`01_start.sh`:

- Stops and removes a previous E2E stack and volumes.
- Removes generated configuration and TLS files.
- Removes previous Playwright artifacts.
- Creates Playwright artifact directories.
- Builds the Playwright image.
- Runs the Dockerized repository lint suite.

The lint suite includes Bash syntax, ShellCheck, SQLFluff, yamllint,
markdownlint, actionlint, Playwright source validation, and Docker Compose
configuration validation.

### 2. Database and ORDS without APEX

`02_no_apex.sh`:

- Runs setup with `INSTALL_APEX=N`.
- Verifies normal project configuration and TLS files are still generated.
- Applies E2E credentials and host bindings.
- Starts Database and ORDS.
- Verifies APEX installation files are absent.
- Verifies APEX is not registered in the PDB.
- Verifies the example workspace schema does not exist.
- Verifies DBMS_CLOUD remains valid.
- Verifies `PDBADMIN` is REST-enabled.
- Runs the browser tests.

The database volume is preserved for the next case so the suite can verify
that APEX can be enabled later without rebuilding the database.

### 3. Earlier APEX installation and in-place upgrade

`03_earlier_apex.sh`:

1. Stops containers while preserving the existing database volume.
2. Downloads the configured earlier APEX distribution.
3. Starts Database and ORDS so APEX is installed into the existing database.
4. Captures the installed earlier database APEX version.
5. Verifies APEX version, installation-file version, schema roles, REST
   enablement, DBMS_CLOUD, and clean persistence state.
6. Creates pre-upgrade persistence data.
7. Runs browser tests against the earlier APEX environment.
8. Stops containers while preserving the database volume.
9. Runs setup with the default latest APEX source.
10. Starts Database and ORDS against the existing database volume.
11. Verifies that the database APEX version changed.
12. Verifies the upgraded database version matches the downloaded latest APEX
    files.
13. Revalidates APEX, schema roles, REST enablement, and DBMS_CLOUD.
14. Verifies persistence data survived the upgrade.
15. Runs the browser tests after the upgrade.

The latest expected APEX version is read from the downloaded installation
files rather than hardcoded.

### 4. Clean latest-APEX lifecycle

`04_latest_apex.sh`:

- Removes the previous base environment and volumes.
- Removes generated configuration and TLS files.
- Runs setup using the default latest APEX source.
- Applies E2E credentials and host bindings.
- Starts Database and ORDS.
- Reads the expected APEX version from the downloaded files.
- Verifies the shared APEX environment baseline.
- Runs browser tests.

### 5. Ollama and HTTPS gateway

`05_ollama.sh`:

- Adds the configured test model to `OLLAMA_PULL_MODELS`.
- Starts Ollama and the Nginx HTTPS gateway.
- Waits for the services to become healthy.
- Recreates the database container so database startup scripts run again while
  persisted database data remains intact.
- Waits for the Ollama model to become available.
- Waits for ORDS to become healthy.
- Verifies database access through the HTTPS gateway.

The gateway SQL assertion checks both:

- `APEX_WEB_SERVICE`
- `DBMS_CLOUD`

and verifies that the expected model appears in the gateway response.

### 6. Persistence, idempotence, and configuration reset

`06_persistence.sh` verifies:

#### Persistence across restart

- Confirms the persistence sentinel does not exist.
- Creates the persistence sentinel.
- Stops the full stack.
- Restarts Database, ORDS, Ollama, and the gateway.
- Waits for all services to become healthy.
- Verifies gateway access still works.
- Verifies the persistence sentinel still contains the expected value.

#### Idempotent setup rerun

- Stops the runtime stack.
- Calculates checksums for generated configuration and TLS files.
- Runs setup normally.
- Recalculates the checksums.
- Fails if setup changed files that should have been preserved.

#### Configuration reset

- Adds temporary sentinels to generated configuration files.
- Records the CA certificate checksum.
- Runs setup with `RESET_CONFIGURATION_FILES=Y`.
- Verifies the configuration files were regenerated.
- Verifies the valid CA certificate was not rotated.
- Reapplies the E2E credentials and host bindings.

### 7. Destructive rebuild

`07_rebuild.sh`:

- Stops the full stack and deletes persistent Docker volumes.
- Runs setup with `RESET_CONFIGURATION_FILES=Y` and
  `ROTATE_CERTIFICATES=Y`.
- Reapplies E2E credentials and host bindings.
- Starts Database and ORDS from the rebuilt environment.
- Reads the latest APEX installation-file version.
- Verifies the shared APEX environment baseline.
- Verifies the old persistence sentinel is absent.
- Runs browser tests against the rebuilt environment.

## Shared APEX environment assertion

APEX-enabled scenarios use a common acceptance baseline that verifies:

- Database APEX version matches the expected release.
- APEX installation files match the expected release.
- `WKSP_SANDBOX` exists.
- `WKSP_SANDBOX` has `DB_DEVELOPER_ROLE` and `CLOUD_USER_ROLE`.
- The workspace schema is REST-enabled.
- `PDBADMIN` is REST-enabled.
- Required DBMS_CLOUD packages and package bodies are `VALID` in both
  `CDB$ROOT` and `FREEPDB1`.

Scenario-specific checks, such as persistence state, remain in their case
files.

## Playwright browser tests

APEX-enabled Playwright runs execute the complete browser suite.
The no-APEX scenario runs only database-actions.spec.ts as PDBADMIN.

### APEX Administration Services

`apex-admin.spec.ts`:

- Opens the Administration Services sign-in page.
- Captures the login page.
- Enters administrator credentials.
- Signs in.
- Rejects known authentication-error messages.
- Verifies the Administration Services success text.
- Captures the authenticated page.

### APEX development workspace

`apex-workspace.spec.ts`:

- Opens the APEX workspace sign-in page.
- Captures the login page.
- Enters workspace, username, and password.
- Signs in.
- Rejects known authentication-error messages.
- Verifies the App Builder success text.
- Captures the authenticated page.

### Oracle Database Actions

`database-actions.spec.ts` uses the REST-enabled workspace schema.

For the default schema:

```text
WKSP_SANDBOX
```

the normal Database Actions path is derived as:

```text
/ords/wksp_sandbox/_sdw/
```

The original database username is used for authentication; only the URL path
is lowercased.

The test:

- Opens the Database Actions sign-in page.
- Captures the login page.
- Enters database credentials.
- Signs in.
- Verifies the Launchpad.
- Verifies the `Development` tab is selected.
- Verifies the expected user menu.
- Dismisses the optional introductory dark-theme dialog when present.
- Captures the Launchpad.

## Playwright reports and artifacts

Playwright artifacts are stored under:

```text
tests/e2e/artifacts/playwright/
```

Five browser runs are retained separately.

### No-APEX

```text
tests/e2e/artifacts/playwright/report/no-apex/index.html
tests/e2e/artifacts/playwright/output/no-apex/
```

### Earlier APEX

```text
tests/e2e/artifacts/playwright/report/earlier-apex/index.html
tests/e2e/artifacts/playwright/output/earlier-apex/
```

### Upgraded APEX

```text
tests/e2e/artifacts/playwright/report/upgraded-apex/index.html
tests/e2e/artifacts/playwright/output/upgraded-apex/
```

### Clean latest APEX

The current run name is `initial`:

```text
tests/e2e/artifacts/playwright/report/initial/index.html
tests/e2e/artifacts/playwright/output/initial/
```

### Rebuilt environment

```text
tests/e2e/artifacts/playwright/report/rebuild/index.html
tests/e2e/artifacts/playwright/output/rebuild/
```

Playwright retains trace, screenshot, and video on failure. The specs also
capture explicit milestone screenshots before password entry and after
successful authentication.

## Failure diagnostics

If a registered phase fails, the EXIT handler prints:

- current Compose state;
- recent Database logs;
- recent ORDS logs;
- recent Ollama logs;
- recent HTTPS gateway logs;
- failed phase number;
- failed phase function name;
- resume command when resume metadata is available.

The failed environment remains available for inspection.

Browser failures should be investigated through the retained HTML report,
trace, screenshot, and video.

## Adding a new E2E case

Create a numbered file under:

```text
tests/e2e/cases/
```

For example:

```text
08_new_feature.sh
```

Define a descriptive function:

```bash
verify_new_feature() {
  pass "New feature behaves as expected."
}
```

Register it:

```bash
register_phase \
  "Verify new feature" \
  "verify_new_feature"
```

### Case-development rules

1. Use unique, descriptive function names.
2. Keep function names stable because resume stores them as identifiers.
3. Do not call `phase()` from case functions.
4. Make each phase safe to rerun from its beginning.
5. Split large operations into meaningful resume checkpoints.
6. Put reusable infrastructure in `lib/common.sh`.
7. Keep scenario-specific logic in the case file.
8. Use `pass`, `info`, and `fail` for consistent output.
9. Prefer comments that explain why a lifecycle step is necessary.
10. Add a value to the resume-state allowlist only when a completed phase
    genuinely produces state that a later phase cannot reconstruct.

## Adding SQL assertions

Place reusable SQL assertions under:

```text
tests/e2e/sql/
```

Use:

```bash
run_sys_sql script.sql ...
run_schema_sql script.sql ...
```

for the base stack and:

```bash
run_sys_sql_ollama script.sql ...
run_schema_sql_ollama script.sql ...
```

for the Ollama-enabled stack.

Keep assertion success messages focused on the state that was observed. The
surrounding E2E phase should explain why that state matters.

## Adding Playwright coverage

Add a new `*.spec.ts` under:

```text
tests/e2e/ui/
```

Reuse `helpers.ts` for:

- required environment variables;
- filling compatible visible inputs;
- username/password entry;
- login-button discovery;
- authentication-error checks;
- screenshot capture.

Avoid duplicating generic login selector logic unless an application genuinely
has a different login flow.

The Playwright image validates test registration with:

```text
npx playwright test --list
```

The repository lint workflow builds that image, so syntax and local-import
errors are checked by local linting and GitHub Actions.

## Run repository checks directly

The E2E suite runs lint automatically, but the checks can also be run
independently:

```bash
./tests/lint/run.sh
```

GitHub Actions uses the same lint entry point.

## Current coverage boundaries

The current suite does not exercise as full acceptance scenarios:

- NVIDIA GPU execution through `compose/ollama.cuda.yml`.
- Exact value assertions for every configurable APEX instance and workspace
  parameter.
