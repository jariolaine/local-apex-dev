# Local Oracle 26ai Free, APEX & Ollama Dev Environment

Docker Compose setup for running Oracle Database 26ai Free, ORDS, APEX,
and Ollama for local large language models (LLMs), with an internal
HTTPS gateway that allows APEX and DBMS_CLOUD in Oracle Database to
access Ollama.

The project automates the main setup tasks:

- A temporary setup container prepares configuration files, Docker volumes,
  local TLS certificates, and—unless disabled—APEX installation files.
- Database startup scripts install and configure DBMS_CLOUD and create or
  reuse an Oracle wallet for HTTPS connections.
- The ORDS container installs or upgrades APEX when APEX installation
  files are available.
- When Ollama is enabled, selected models are downloaded in the background
  while APEX is being installed.

> **Note:** This environment is intended strictly for local development,
testing, and learning. It is not designed or supported for production use.

## Prerequisites

- **Docker Desktop** on Windows or macOS, or **Docker Engine** on Linux,
  with the `docker compose` plugin.
- **Git** for cloning this repository.
- **Optional, Linux only:** NVIDIA Container Toolkit when using
  Ollama with an NVIDIA GPU.

Ollama models may require significant memory, disk space, and download time.
Choose models that are suitable for your computer.

## Quick Start

Clone this repository:

```console
git clone https://github.com/jariolaine/local-apex-dev.git
cd local-apex-dev
```

### Run Automatic Setup

The setup container prepares the local configuration files, initializes
Docker named volumes, downloads Oracle APEX installation files when required,
and ensures that the TLS certificates required by the internal HTTPS gateway
are available.

Windows & macOS:

```console
docker compose run --rm setup
```

Linux:

```console
docker compose run --rm \
  -e HOST_UID=$(id -u) \
  -e HOST_GID=$(id -g) \
  setup
```

> **Note:** The setup may take some time while Docker downloads the required
  image and the container downloads and extracts APEX installation files.

#### Skip APEX Installation

If you don't need APEX, you can skip download by passing environment variable
`INSTALL_APEX=N`.

> **Note:** `INSTALL_APEX=N` only skips downloading APEX installation files.
> It does not remove existing APEX files or uninstall APEX from
> an existing database.
> If the initial setup was run with APEX disabled,
> run setup again without `INSTALL_APEX=N` to prepare the APEX files.
> APEX will then be installed during the next Database and ORDS startup.

Windows & macOS:

```console
docker compose run --rm -e INSTALL_APEX=N setup
```

Linux:

```console
docker compose run --rm \
  -e HOST_UID=$(id -u) \
  -e HOST_GID=$(id -g) \
  -e INSTALL_APEX=N  \
  setup
```

### Review the Configuration

Before starting the environment, review these generated files:

- `.env`
- `apex_instance_parameters.yaml`
- `apex_workspaces.yaml`

At minimum, set ORACLE_PWD in `.env`.

> **Warning:** The generated files may contain plaintext development
  credentials. Do not commit them to source control or reuse their passwords
  in another environment.

Ollama and the HTTPS gateway are disabled by default.
To enable them, open `.env` and uncomment either
the CPU or NVIDIA GPU `COMPOSE_FILE` option.

### Start the Containers

```console
docker compose up -d
```

The first startup takes longer because Docker downloads the required images,
the database scripts configure missing components.
When APEX installation files are available, ORDS installs or upgrades
APEX when required.

Check the container status:

```console
docker compose ps
```

Follow the ORDS startup log:

```console
docker compose logs -f ords
```

Follow the detailed APEX installation log:

```console
docker compose exec -it ords \
  tail -f /tmp/install_logs/apex_install.log
```

Press `Ctrl+C` to stop viewing a log. This does not stop the containers.

The APEX web interface is ready when the ORDS container reports healthy.

When Ollama is enabled, large model downloads may continue after APEX becomes
available.

### Access the Environment

- **Database Actions:** [http://localhost:8181/ords/sql-developer](http://localhost:8181/ords/sql-developer)
  - Sign in as `PDBADMIN` using `ORACLE_PWD` from `.env`.
- **Database administration with SQLcl:**

  ```console
  docker compose exec -it ords sh -c \
    'sql -L system/$ORACLE_PWD@$DBHOST:$DBPORT/$DBSERVICENAME'
  ```

When APEX is installed:

- **APEX Administration Service:** [http://localhost:8181/ords/apex_admin](http://localhost:8181/ords/apex_admin)
  - The administrator credentials are configured in `.env`.
- **APEX Development Service:** [http://localhost:8181/ords/apex](http://localhost:8181/ords/apex)
  - Workspace and user credentials are configured in `apex_workspaces.yaml`.

When Ollama is enabled, Oracle Database accesses Ollama through
the internal HTTPS gateway at:

```text
https://ollama-api-gateway
```

### Stop the Containers

```console
docker compose down
```

This removes the containers but preserves data stored in Docker named volumes.

## Configuration

### Environment Settings

The `.env` file contains:

- Database and APEX administrator credentials.
- Optional database and ORDS host port bindings.
- Optional ORDS debug logging.
- Optional archive logging and force logging settings.
- Optional Docker Compose files for CPU or NVIDIA GPU support.
- Ollama model download and performance settings.
- Optional image tags for the Database, ORDS, Ollama, Nginx, and
  setup container.

### APEX Instance Parameters

`apex_instance_parameters.yaml` defines global APEX instance settings.

Configured values are applied during ORDS startup, so you can update the file
and restart the environment to apply changes.

### APEX Workspaces

`apex_workspaces.yaml` defines workspaces, database schemas, workspace users,
developer privileges, and workspace parameters.

New workspaces are created automatically. When creating a workspace,
its configured database schema is created if it does not already exist.

Existing workspaces are not recreated. Their schema association and users
are not automatically changed, but configured workspace parameters
are reapplied during startup.

Newly created schemas are REST-enabled and granted the
`DB_DEVELOPER_ROLE` and `CLOUD_USER_ROLE`.

## How It Works Under the Hood

### Setup Container

The temporary `setup` container performs tasks that would otherwise require
utilities such as `curl`, `unzip`, and `openssl` on the host.

It prepares the configuration files, APEX files, named volume permissions,
and the local CA and server certificate used by the HTTPS gateway.

### Database Startup

The database container executes the scripts in `db-startup/` in numeric order.

The scripts:

- Adjust Oracle listener and TNS hostname configuration for
  container networking.
- Start requested Ollama model downloads in the background, allowing them to
  run while the ORDS container installs APEX.
- Install or update the `DBMS_CLOUD` package family when required.
- Configure Network Access Control Lists (ACLs) and the `CLOUD_USER_ROLE`.
- Create or reuse the Oracle wallet for outbound HTTPS connections.

Where appropriate, the scripts check existing state and avoid repeating
provisioning that has already completed.

The `EXECUTE` privilege is granted to the `CLOUD_USER_ROLE` on the
following packages:

- `DBMS_CLOUD`
- `DBMS_CLOUD_REPO`
- `DBMS_CLOUD_PIPELINE`
- `DBMS_CLOUD_NOTIFICATION`
- `DBMS_CLOUD_AI`
- `DBMS_CLOUD_AI_AGENT`

### ORDS Startup

The ORDS container runs the APEX installation into Oracle Database
when required.

It then executes the scripts in `ords-entrypoint.d/` in numeric order to
configure ORDS, apply APEX instance parameters, and provision the configured
workspaces, schemas, users, and workspace parameters.

## Upgrade APEX

By default the environment setup container uses the latest APEX download link.
Once initial setup has run, a new APEX version will not be downloaded.
To force a new version download, set `FORCE_DOWNLOAD_LATEST_APEX`
environment variable and run setup again.
If the downloaded APEX version is newer than the installed version,
ORDS upgrades APEX during the next environment startup.

Stop the project containers before refreshing the APEX installation files:

```console
docker compose down
```

Windows & macOS:

```console
docker compose run --rm -e FORCE_DOWNLOAD_LATEST_APEX=Y setup
```

Linux:

```console
docker compose run --rm \
  -e HOST_UID=$(id -u) \
  -e HOST_GID=$(id -g) \
  -e FORCE_DOWNLOAD_LATEST_APEX=Y \
  setup
```

Then restart project:

```console
docker compose up -d
```

## Troubleshooting

Check the current container state:

```console
docker compose ps
```

View database logs:

```console
docker compose logs -f db
```

View ORDS startup logs:

```console
docker compose logs -f ords
```

A container that remains unhealthy usually provides the most useful error
information in its service log.

To remove persistent Docker data and regenerate the project configuration
files, stop the containers and remove the named volumes.

> **Warning:** The `-v` command permanently removes the database, APEX files,
  ORDS configuration, and downloaded Ollama models.

```console
# DANGER ZONE: This permanently removes all named volumes.
docker compose down -v
```

Run setup again:

> **Important:** You must stop all project containers before running
  the setup again.
> By default, existing configuration files and valid TLS certificates are
  preserved. To explicitly overwrite them, pass one or both of these
  environment variables to the setup container:
>
> - `RESET_CONFIGURATION_FILES=Y`
> - `ROTATE_CERTIFICATES=Y`

Windows & macOS:

```console
docker compose run --rm -e RESET_CONFIGURATION_FILES=Y setup
```

Linux:

```console
docker compose run --rm \
  -e HOST_UID=$(id -u) \
  -e HOST_GID=$(id -g) \
  -e RESET_CONFIGURATION_FILES=Y \
  setup
```

Review the regenerated configuration and start the environment.
