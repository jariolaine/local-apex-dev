#!/bin/bash

## Variables
PROJECT_HOME="$(dirname -- "$(realpath -- "$0")")"

APEX_DOWNLOAD_URL="https://download.oracle.com/otn_software/apex/apex-latest.zip"
APEX_INSTANCE_CONFIG="./apex_instance_parameters.yaml"
APEX_WORKSPACE_CONFIG="./apex_workspaces.yaml"

echo "INFO: Setup started."
echo "======================================="

cd "${PROJECT_HOME}"

# Create directories for container volumes
echo "INFO: Creating directories for containers persistent volumes."

mkdir -p ./oradata ./ords-config
chgrp 54321 ./oradata ./ords-config
chmod g+rw ./oradata ./ords-config

# Download and extract APEX install files
echo "INFO: Downloading APEX install files..."
curl -sS -z ./apex-latest.zip -R -O "${APEX_DOWNLOAD_URL}" && \
echo "INFO: Downloaded APEX install files successfully."

if [ -f "./apex-latest.zip" ]; then
  echo "INFO: Extracting APEX install files..."
  unzip -q -u ./apex-latest.zip "apex/*"
  chgrp -R 54321 ./apex
  chmod -R g+rw ./apex
  chmod -R go-wx+Xr ./apex/images
  #rm ./apex-latest.zip
else
  echo "ERROR: Failed to download apex-latest.zip. Aborting setup."
  exit 1
fi

# Copy environment variables template
if [ ! -f "./.env" ]; then
  echo "INFO: Creating environment variables file (.env)."
  cp ./env.template ./.env
else
  echo "INFO: Skipping .env creation; it already exists."
fi

# Copy APEX instance configuration template
if [ ! -f "${APEX_INSTANCE_CONFIG}" ]; then
  echo "INFO: Creating APEX instance configuration file (${APEX_INSTANCE_CONFIG})."
  cp "${APEX_INSTANCE_CONFIG}.template" "${APEX_INSTANCE_CONFIG}"
else
  echo "INFO: Skipping APEX instance config; it already exists."
fi

# Copy APEX workspaces configuration template
if [ ! -f "${APEX_WORKSPACE_CONFIG}" ]; then
  echo "INFO: Creating APEX workspaces configuration file (${APEX_WORKSPACE_CONFIG})."
  cp "${APEX_WORKSPACE_CONFIG}.template" "${APEX_WORKSPACE_CONFIG}"
else
  echo "INFO: Skipping APEX workspace config; it already exists."
fi

echo "======================================="
echo "INFO: Setup script finished successfully!"