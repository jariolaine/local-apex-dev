# Local Oracle 26ai Free, APEX & Ollama Dev Environment

A beginner-friendly Docker Compose setup for running a local Oracle Database 26ai Free instance with ORDS, APEX, and Ollama for local Large Language Models (LLMs).

This project automates the entire process: downloading, installing, and configuring APEX within the database container on startup, while providing a ready-to-use local AI endpoint.

> **Note:** This environment is intended strictly for development and learning purposes.

## Prerequisites

*   **Docker Engine** (with the `docker compose` plugin).
*   **Linux Tools**: `curl` and `unzip` are required for the automated setup script.
*   **Optional**: NVIDIA Container Toolkit (only if you intend to enable GPU acceleration for Ollama).

## Quick Start

To begin, clone this repository to your local machine:

```bash
git clone https://github.com/jariolaine/local-apex-dev.git
cd local-apex-dev
```

### Automated Setup (Recommended)

For Linux users (or Windows/macOS users utilizing WSL or the macOS Terminal), a single script handles all initialization tasks:
- Generating config files from templates.
- Creating persistent volume directories.
- Downloading the latest Oracle APEX and extracting it.

Run automatic setup:

```bash
chmod u+x ./setup.sh
./setup.sh
```

### Manual Setup (Optional)

If you prefer manual control or are on a platform where you cannot execute `setup.sh`:

1.  **Environment Variables**: Copy `env.template` to `.env`.
2.  **APEX Instance Parameters**: Copy `apex_instance_parameters.yaml.template` to `apex_instance_parameters.yaml`.
3.  **APEX Workspaces**: Copy `apex_workspaces.yaml.template` to `apex_workspaces.yaml`.

Download the [latest Oracle APEX](https://download.oracle.com/otn_software/apex/apex-latest.zip), and extract it into a directory named `apex`.

Linux users must give permission to the persistent volume directories:

```bash
mkdir -p ./oradata ./ords-config
chgrp -R 54321 ./oradata ./ords-config ./apex
chmod g+w ./oradata ./ords-config ./apex
chmod -R g+r ./oradata ./ords-config ./apex
chmod -R go-wx+rX ./apex/images
chmod -R +r ./db-startup ./ords-entrypoint.d
```

### Start Containers

> **Important**: Review and update your `.env`, `apex_instance_parameters.yaml`, and `apex_workspaces.yaml` files
> to match your environment requirements (especially passwords) before proceeding.

> **Ollama AI Support:** By default, the environment starts *without* Ollama to save system resources.
> To enable local AI capabilities (for either CPU or NVIDIA GPU), open your `.env` file
> and uncomment the desired `COMPOSE_FILE` option before starting the containers.

Start containers:

```bash
docker compose up -d
```

> **Note:** The first startup will take significantly longer.
> Docker must first download (pull) the required container images,
> and then the system must set up the database and install APEX from scratch into the fresh Oracle database.
> Subsequent startups are much faster.

#### Checking APEX Installation Progress

You can monitor the background installation process in two ways:

To watch the detailed APEX database installation in real-time, run:

```bash
docker exec -it ords-node-1 tail -f /tmp/install_logs/apex_install.log
```

To watch the general ORDS server startup logs, run:

```bash
docker logs -f ords-node-1
```

> **Tip:** You can press `Ctrl + C` at any time to exit the log viewer.
> This will not stop the installation running in the background.

You will know the setup is fully complete and ready to use when the log output settles and indicates that the Oracle REST Data Services server has started.

Alternatively, you can wait for both containers to show as `(healthy)`:

```bash
docker ps -f name=db-26ai-free -f name=ords-node-1
```

### Accessing Your Environment

Once running, access your environment at:


*   **APEX Administration Service**: [http://localhost:8181/ords/apex_admin](http://localhost:8181/ords/apex_admin)
    *   **Credentials**: Instance admin user name and user password are defined in the `.env` file.
*   **APEX Development Service**: [http://localhost:8181/ords/apex](http://localhost:8181/ords/apex)
    *   **Credentials**: Workspace names and user credentials are defined in the `apex_workspaces.yaml` file.
*   **Database (SQLcl)**: Connect as the SYSTEM user, for example:
    ```bash
    docker exec -it ords-node-1 sh -c 'sql -L system/$ORACLE_PWD@$DBHOST:$DBPORT/$DBSERVICENAME'
    ```
*   **Ollama API (Internal):** Accessible from within the Oracle Database via `http://ollama:11434/`.

### Stop Containers

Stop containers when finished:

```bash
docker compose down
```

## Configuration Files Overview

This environment relies on three primary configuration files to automate the provisioning of your Oracle Database, APEX, ORDS, and Ollama containers. Below is a summary of each file and the key topics they control.


### The Environment File (`.env`)

This file defines the core system passwords, connection settings, and hardware tuning variables. It is the foundation of your Docker Compose deployment.

**Key Topics:**

* **Database & ORDS Security:** Sets the master `ORACLE_PWD` used for the SYS, SYSTEM, and PDBADMIN database users.
* **ORDS Connection Settings:** Configures how the REST Data Services communicate with the database,
including hostnames, ports, service names, and debug logging.
* **Database Startup Features:** Offers optional toggles for advanced recovery features like Archive Logging and Force Logging.
* **APEX Administration:** Defines the username, password, and email for the main APEX Instance Administrator (INTERNAL workspace).
* **Ollama Performance Tuning:** Includes settings to optimize local Large Language Models based on your available RAM/VRAM,
such as context length, keep-alive duration, flash attention, and parallel request limits.
* **Ollama Model Auto-Pull:** Uses the `OLLAMA_PULL_MODELS` variable to define a comma-separated list of models
(e.g., `llama3.1:8b,phi3:mini`) that will automatically download in the background when the environment starts.

---

### APEX Instance Parameters (`apex_instance_parameters.yaml`)

This file dictates the global configuration settings applied to the entire Oracle APEX instance.
These settings are applied during every startup, allowing you to easily modify instance parameters over time.

---

### APEX Workspaces (`apex_workspaces.yaml`)

This file automates the creation and configuration of individual APEX workspaces and their associated users.

**Key Topics:**
* **Schema Provisioning:** Maps workspaces to specific database schemas. If a schema does not exist, the setup automatically creates it with the necessary privileges and enables REST. If it already exists, it is associated with the workspace without modifying its existing state.
* **Workspace Users:** Defines administrative and developer accounts for each workspace, including their emails, initial passwords, and whether they must change their password on the first login.
* **Workspace-Level Parameters:** Allows you to apply specific settings to individual workspaces.