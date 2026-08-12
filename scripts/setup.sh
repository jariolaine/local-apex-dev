#!/bin/bash

## Variables
PROJECT_HOME="$(dirname -- "$(realpath -- "$0")")"

APEX_DOWNLOAD_URL="https://download.oracle.com/otn_software/apex/apex-latest.zip"
APEX_INSTANCE_CONFIG="./apex_instance_parameters.yaml"
APEX_WORKSPACE_CONFIG="./apex_workspaces.yaml"

echo "INFO: Setup started."
echo "======================================="

cd "${PROJECT_HOME}"

# Download and extract APEX install files
echo "INFO: Downloading APEX install files..."
curl -sS -z ./apex-latest.zip -R -O "${APEX_DOWNLOAD_URL}" && \
echo "INFO: Downloaded APEX install files successfully."

if [ -f "./apex-latest.zip" ]; then
  echo "INFO: Extracting APEX install files..."
  unzip -q -u ./apex-latest.zip "apex/*"
  #rm ./apex-latest.zip
else
  echo "ERROR: Failed to download apex-latest.zip. Aborting setup."
  exit 1
fi

# Create directories for container volumes
echo "INFO: Creating directories for containers persistent volumes."
mkdir -p ./oradata ./ords-config

echo "INFO: Setting permissions for containers persistent volumes."
chgrp -R 54321 ./oradata ./ords-config ./apex
chmod g+w ./oradata ./ords-config ./apex
chmod -R g+r ./oradata ./ords-config ./apex
chmod -R go-wx+rX ./apex/images
chmod -R +r ./db-startup ./ords-entrypoint.d

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