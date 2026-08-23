#!/bin/bash
set -Eeuo pipefail

# ------------------------------------------------------------------------------
# Configuration Variables
# ------------------------------------------------------------------------------
LATEST_APEX_DOWNLOAD_URL="https://download.oracle.com/otn_software/apex/apex-latest.zip"
TARGET_CONTAINERS=("db" "ords" "nginx" "ollama")
ALL_CONTAINERS_STOPPED="TRUE"
GENERATE_NEW_CERTS="FALSE"

CERT_DIR="./ssl"
CERT_TMP_DIR="./.ssl.new"
CERT_BACKUP_DIR="./.ssl.previous"
CERT_DNS="ollama-api-gateway"

APEX_INSTANCE_CONFIG="./apex_instance_parameters.yaml"
APEX_WORKSPACE_CONFIG="./apex_workspaces.yaml"

APEX_VERSION_FILE="/volumes/apex/images/apex_version.txt"

APEX_MARKER_DIR="/volumes/apex/.local-apex-dev"

APEX_FILES_MARKER="${APEX_MARKER_DIR%/}/apex-download_url.txt"

SSL_WALLET="/volumes/oradata/ssl_wallet"

# INSTALL_APEX controls only preparation of APEX installation files.
# Project configuration and TLS files are generated regardless so APEX can
# be enabled later without rebuilding the database environment.
INSTALL_APEX="${INSTALL_APEX:-TRUE}"

# A forced refresh always targets the canonical latest APEX URL, even when
# APEX_DOWNLOAD_URL was previously overridden with an older release.
FORCE_DOWNLOAD_LATEST_APEX="${FORCE_DOWNLOAD_LATEST_APEX:-FALSE}"
RESET_CONFIGURATION_FILES="${RESET_CONFIGURATION_FILES:-FALSE}"
ROTATE_CERTIFICATES="${ROTATE_CERTIFICATES:-FALSE}"

APEX_DOWNLOAD_URL="${APEX_DOWNLOAD_URL:-${LATEST_APEX_DOWNLOAD_URL}}"


# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------
cleanup() {
  rm -rf -- "${CERT_TMP_DIR}"
}

trap cleanup EXIT

is_true() {
  case "${1^^}" in
    1|Y|YES|TRUE) return 0 ;;
    *) return 1 ;;
  esac
}

error() {
  echo "ERROR : $*" >&2
  return 1
}

info() {
  echo "INFO : $*"
}

# Extract APEX version from installation files
get_apex_files_version() {
  local version
  local file="${1:-${APEX_VERSION_FILE}}"

  [[ -s "$file" ]] || return 1

  version="$(<"$file")"
  [[ -n "$version" ]] || return 1

  printf '%s\n' "${version##* }"
}

certs_are_valid() {

  local certDir="${1}"

  # Verify all required files exist.
  [[ -s "${certDir}/ca.cer" ]] || return 1
  [[ -s "${certDir}/ca.key" ]] || return 1
  [[ -s "${certDir}/server.cer" ]] || return 1
  [[ -s "${certDir}/server.key" ]] || return 1
  [[ -s "${certDir}/fullChain.cer" ]] || return 1

  # Verify that the server certificate is signed by the local CA and matches the expected hostname.
  if ! openssl verify -CAfile "${certDir}/ca.cer" -verify_hostname "${CERT_DNS}" "${certDir}/server.cer" &>/dev/null; then
    return 1
  fi
  if ! openssl verify -CAfile "${certDir}/ca.cer" -verify_hostname "${CERT_DNS}" "${certDir}/fullChain.cer" &>/dev/null; then
    return 1
  fi

  # Verify that the server private key matches the server certificate.
  # Compare extracted public keys because the project uses elliptic-curve keys.
  local key_pub cert_pub chain_pub
  key_pub=$(openssl pkey -pubout -in "${certDir}/server.key" 2>/dev/null | openssl sha256)
  cert_pub=$(openssl x509 -pubkey -noout -in "${certDir}/server.cer" 2>/dev/null | openssl sha256)
  chain_pub=$(openssl x509 -pubkey -noout -in "${certDir}/fullChain.cer" 2>/dev/null | openssl sha256)

  if [[ "${key_pub}" != "${cert_pub}" ]]; then
    return 1
  fi

  if [[ "${key_pub}" != "${chain_pub}" ]]; then
    return 1
  fi

  return 0
}

set_owner_and_group() {
  if [ -n "${HOST_UID:-}" ]; then
    info "Setting ${1} ownership to UID (${HOST_UID})."
    chown -R "${HOST_UID}" "${1}"
  else
    info "HOST_UID not set. Skipping ${1} ownership mapping."
  fi
  if [ -n "${HOST_GID:-}" ]; then
    info "Setting ${1} group to GID (${HOST_GID})."
    chgrp -R "${HOST_GID}" "${1}"
  else
    info "HOST_GID not set. Skipping ${1} group mapping."
  fi
}

apex_files_are_valid() {
  [[ -s "/volumes/apex/apexins.sql" ]] &&
  [[ -s "/volumes/apex/apxchpwd.sql" ]] &&
  [[ -s "${APEX_VERSION_FILE}" ]] &&
  [[ -s "${APEX_FILES_MARKER}" ]] &&
  [[ "$(cat "${APEX_FILES_MARKER}")" == "${APEX_DOWNLOAD_URL}" ]]
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

echo "============================================================"
info "Setup started."

info "Verifying other containers are not running. This may take a few seconds..."
for container in "${TARGET_CONTAINERS[@]}"; do
  # ping arguments:
  # -c 1    : Send exactly 1 ping request.
  # -W 1  : Timeout after 1 second if there is no response.
  if ping -c 1 -W 1 "$container" &> /dev/null; then
    ALL_CONTAINERS_STOPPED="FALSE"
  fi
done

# Final evaluation.
if ! is_true "${ALL_CONTAINERS_STOPPED}"; then
  error "One or more containers are still running." \
    "Please stop all containers in this Docker Compose project before running setup. Aborting."
  exit 1
fi

if is_true "${RESET_CONFIGURATION_FILES}"; then
  info "RESET_CONFIGURATION_FILES is set to true. Removing old configuration files."
  rm -rf "${APEX_INSTANCE_CONFIG}" "${APEX_WORKSPACE_CONFIG}" ./.env
fi

if ! is_true "${INSTALL_APEX}"; then
  info "INSTALL_APEX is set to false; APEX installation files will not be downloaded. Skipping."
else
  # Download APEX installation files and extract them to the named volume.
  if is_true "${FORCE_DOWNLOAD_LATEST_APEX}" || ! apex_files_are_valid; then

    if is_true "${FORCE_DOWNLOAD_LATEST_APEX}"; then
      APEX_DOWNLOAD_URL="${LATEST_APEX_DOWNLOAD_URL}"

      info \
        "FORCE_DOWNLOAD_LATEST_APEX is set to true. " \
        "Forcing latest APEX installation files download."

      if existing_apex_version="$(get_apex_files_version 2>/dev/null)"; then
        info \
          "Overwriting existing APEX installation files " \
          "(version: ${existing_apex_version})."
      else
        info \
          "Existing APEX version metadata is unavailable or invalid; " \
          "replacing the cached installation files."
      fi
    fi

    info "Downloading APEX installation archive..."

    if ! curl --fail --location --show-error -sS -o /tmp/apex.zip "${APEX_DOWNLOAD_URL}"; then
      error "Failed to download the APEX installation archive."
      exit 1
    fi

    info "APEX installation archive downloaded successfully."
    info "Extracting APEX installation files..."
    rm -rf "${APEX_MARKER_DIR}"
    rm -rf /volumes/apex/*

    if ! unzip -q -o /tmp/apex.zip "apex/**" -d /volumes/; then
      error "Failed to extract the APEX installation archive."
      exit 1
    fi
    if ! extracted_apex_version="$(get_apex_files_version)"; then
      error \
        "Extracted APEX installation does not contain valid version information."
      exit 1
    fi

    info \
      "APEX installation files extracted successfully " \
      "(version: ${extracted_apex_version})."

    mkdir -p "${APEX_MARKER_DIR}"
    echo "${APEX_DOWNLOAD_URL}" > "${APEX_FILES_MARKER}"

  else
    info "APEX installation files exist. Skipping."
  fi
fi

# Copy environment variables template.
if [[ -f "./.env" ]]; then
  info "File .env exists. Skipping."
else
  info "Creating environment variables file (.env)."
  cp ./templates/env.template ./.env
  set_owner_and_group "./.env"
fi

# Copy APEX instance configuration template.
if [[ -f "${APEX_INSTANCE_CONFIG}" ]]; then
  info "File ${APEX_INSTANCE_CONFIG} exists. Skipping."
else
  info "Creating APEX instance configuration file (${APEX_INSTANCE_CONFIG})."
  cp "./templates/${APEX_INSTANCE_CONFIG%.yaml}.template.yaml" "${APEX_INSTANCE_CONFIG}"
  set_owner_and_group "${APEX_INSTANCE_CONFIG}"
fi

# Copy APEX workspaces configuration template.
if [[ -f "${APEX_WORKSPACE_CONFIG}" ]]; then
  info "File ${APEX_WORKSPACE_CONFIG} exists. Skipping."
else
  info "Creating APEX workspaces configuration file (${APEX_WORKSPACE_CONFIG})."
  cp "./templates/${APEX_WORKSPACE_CONFIG%.yaml}.template.yaml" "${APEX_WORKSPACE_CONFIG}"
  set_owner_and_group "${APEX_WORKSPACE_CONFIG}"
fi

# Evaluate whether new certificates are needed.
if is_true "${ROTATE_CERTIFICATES}"; then
  info "ROTATE_CERTIFICATES is set to true. Forcing TLS certificate regeneration."
  GENERATE_NEW_CERTS="TRUE"
elif ! certs_are_valid "${CERT_DIR}"; then
  info "TLS certificates are missing or invalid. Generating new certificates..."
  GENERATE_NEW_CERTS="TRUE"
else
  info "Valid TLS certificates already exist in ${CERT_DIR}. Skipping certificate generation."
fi

# Generate CA and server certificate for HTTPS gateway if required.
if is_true "${GENERATE_NEW_CERTS}"; then

  rm -rf "${CERT_TMP_DIR}"
  mkdir -p "${CERT_TMP_DIR}"

  info "Generating CA certificate private key."
  # Create the CA private key.
  if ! openssl genpkey \
    -algorithm EC \
    -pkeyopt ec_paramgen_curve:P-384 \
    -out "${CERT_TMP_DIR}/ca.key"; then
      error "Failed to generate the CA certificate private key."
      exit 1
  fi

  info "Generating CA certificate."
  # Create the CA certificate.
  if ! openssl req \
    -new \
    -x509 \
    -key "${CERT_TMP_DIR}/ca.key" \
    -sha256 \
    -days 3600 \
    -out "${CERT_TMP_DIR}/ca.cer" \
    -subj "/CN=Local Docker CA" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -addext "subjectKeyIdentifier=hash"; then
      error "Failed to generate the CA certificate."
      exit 1
  fi

  # Define server certificate extensions.
  cat > "${CERT_TMP_DIR}/server.ext" << EOF
subjectAltName=DNS:${CERT_DNS}
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=serverAuth
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF

  info "Generating server certificate private key."
  # Create the server private key.
  if ! openssl genpkey \
    -algorithm EC \
    -pkeyopt ec_paramgen_curve:P-384 \
    -out "${CERT_TMP_DIR}/server.key"; then
      error "Failed to generate the server certificate private key."
      exit 1
  fi

  info "Generating server certificate signing request for ${CERT_DNS}."
  # Create the server certificate signing request.
  if ! openssl req \
    -new \
    -key "${CERT_TMP_DIR}/server.key" \
    -out "${CERT_TMP_DIR}/server.csr" \
    -subj "/CN=${CERT_DNS}"; then
      error "Failed to generate the server certificate signing request."
      exit 1
  fi

  # Sign the server certificate.
  info "Signing server certificate for ${CERT_DNS}."
  if ! openssl x509 \
    -req \
    -days 3600 \
    -sha256 \
    -in "${CERT_TMP_DIR}/server.csr" \
    -CA "${CERT_TMP_DIR}/ca.cer" \
    -CAkey "${CERT_TMP_DIR}/ca.key" \
    -CAcreateserial \
    -extfile "${CERT_TMP_DIR}/server.ext" \
    -out "${CERT_TMP_DIR}/server.cer"; then
      error "Failed to sign the server certificate."
      exit 1
  fi

  # Create full certificate chain.
  info "Creating full chain certificate from server and CA certificates."
  if ! cat "${CERT_TMP_DIR}/server.cer" "${CERT_TMP_DIR}/ca.cer" > "${CERT_TMP_DIR}/fullChain.cer"; then
    error "Failed to create the full chain certificate."
    exit 1
  fi

  # Verify generated certificates.
  info "Verifying generated TLS certificates..."
  if certs_are_valid "${CERT_TMP_DIR}"; then
    info "Generated TLS certificates are valid."
  else
    error "Generated TLS certificates are invalid."
    exit 1
  fi

  if ! rm -rf "${CERT_BACKUP_DIR}"; then
    error "Failed to remove the previous TLS certificate backup directory."
    exit 1
  fi

  if [[ -d "${CERT_DIR}" ]]; then
    if ! mv "${CERT_DIR}" "${CERT_BACKUP_DIR}"; then
      error "Failed to backup the existing TLS certificate directory."
      exit 1
    fi
  fi

  if mv "${CERT_TMP_DIR}" "${CERT_DIR}"; then
    if ! rm -rf "${CERT_BACKUP_DIR}"; then
      error "Failed to remove the previous TLS certificate backup directory."
      exit 1
    fi
    info "New TLS certificates activated successfully."
  else
    error "Failed to activate the new TLS certificates."

    if ! rm -rf "${CERT_DIR}"; then
      error "Failed to remove the new TLS certificate directory."
      exit 1
    fi

    if [[ -d "${CERT_BACKUP_DIR}" ]]; then
      if ! mv "${CERT_BACKUP_DIR}" "${CERT_DIR}"; then
        error "Failed to restore the previous TLS certificate directory."
        exit 1
      fi
    fi

    exit 1
  fi

  # Set ownership and group for the active certificate directory.
  if ! set_owner_and_group "${CERT_DIR}"; then
    error "Failed to set ownership and group for ${CERT_DIR}."
    exit 1
  fi

  # Remove the existing Oracle wallet so it is recreated with the new local CA certificate.
  info "Removing any existing Oracle wallet so it can be recreated with the new CA certificate."
  if ! rm -rf "${SSL_WALLET}"; then
    error "Failed to remove the existing Oracle wallet."
    exit 1
  fi

fi

# ------------------------------------------------------------------------------
# Database and ORDS Volume Permissions
# ------------------------------------------------------------------------------
# The APEX, database, and ORDS configuration data use Docker named volumes.
# Assign them to the Oracle container user and group (54321:54321).
info "Setting named volume ownership to UID (54321) and GID (54321)."
if ! chown -R 54321:54321 /volumes; then
  error "Failed to set ownership for /volumes."
  exit 1
fi

if ! chmod -R ug+rw+X /volumes; then
  error "Failed to set permissions for /volumes."
  exit 1
fi

trap - EXIT

info "Setup completed successfully."

# Provide helpful next steps to user
echo "=========================================================="
echo "Next steps:"
echo "  - Set ORACLE_PWD in .env file and review other variables."
if is_true "${INSTALL_APEX}"; then
  echo "  - Review APEX instance configuration: ${APEX_INSTANCE_CONFIG}."
  echo "  - Review APEX workspaces configuration: ${APEX_WORKSPACE_CONFIG}."
fi
echo "  - Start the environment:"
echo "      docker compose up -d"
echo "============================================================"
