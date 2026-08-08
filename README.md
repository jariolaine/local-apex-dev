# Local Oracle 26ai Free & APEX Dev Environment

A beginner-friendly Docker Compose setup for running a local Oracle Database 26ai Free instance with ORDS and APEX.

This project automates the entire process: downloading, installing, and configuring APEX within the database container on startup.

> **Note:** This environment is intended strictly for development and learning purposes.

## Prerequisites

*   **Docker Engine** (with the `docker compose` plugin).
*   **Linux Tools**: `curl` and `unzip` are required for the automated setup script.

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

```bash
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
chgrp -R 54321 ./oradata ./ords-config ./apex
chmod g+w ./oradata ./ords-config ./apex
chmod -R g+r ./oradata ./ords-config ./apex
chmod -R go-wx+rX ./apex/images
```

## Start Containers

> **Important**: Review and update your `.env`, `apex_instance_parameters.yaml`, and `apex_workspaces.yaml` files
> to match your environment requirements (especially passwords) before proceeding.

Start the database and ORDS containers:

```bash
docker compose up -d
```

> **Note:** The first startup will take several minutes as it installs APEX into the fresh Oracle database. Subsequent startups are faster.

### Checking APEX Installation Progress

Because the first startup installs APEX from scratch into the database, it can take several minutes depending on your system's hardware.
You can monitor the installation progress in two ways:

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

Alternatively, you can wait for the containers status to change to (healthy):

```bash
docker ps -f name=db-26ai-free -f name=ords-node-1
```

## Accessing Your Environment

Once running, access your environment at:


*   **APEX Administration Service**: [http://localhost:8181/ords/apex_admin](http://localhost:8181/ords/apex_admin)
    *   **Credentials**: Instance admin user name and user credentials are defined in the `.env` file.
*   **APEX Development Service**: [http://localhost:8181/ords/apex](http://localhost:8181/ords/apex)
    *   **Credentials**: Workspace names and user credentials are defined in the `apex_workspaces.yaml` file.
*   **Database (SQLcl)**: Connect as the SYSTEM user, for example:

    ```bash
    docker exec -it ords-node-1 sh -c 'sql -L system/$ORACLE_PWD@$DBHOST:$DBPORT/$DBSERVICENAME'
    ```

## Stop Containers

Stop all containers when finished:

```bash
docker compose down
```