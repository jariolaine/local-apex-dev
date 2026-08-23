#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# SSL/TLS Wallet Creation Script
#
# Creates an Oracle auto-login wallet containing the local gateway CA and the
# standard certificates required by the DBMS_CLOUD package family.
# ==============================================================================

# ------------------------------------------------------------------------------
# Configuration Variables
# ------------------------------------------------------------------------------
WORK_DIR="/tmp/dbms-cloud-wallet"

CA_DOWNLOAD_URL="https://objectstorage.us-phoenix-1.oraclecloud.com/p/KB63IAuDCGhz_azOVQ07Qa_mxL3bGrFh1dtsltreRJPbmb-VwsH2aQ4Pur2ADBMA/n/adwcdemo/b/CERTS/o/dbc_certs.tar"
CA_CERT_DIR="${WORK_DIR}/standard-certificates"
CA_CERT_ARCHIVE="${WORK_DIR}/dbc_certs.tar"
LOCAL_CA_CERT="/home/oracle/ssl/local-ca.cer"

SSL_WALLET_DIR="${ORACLE_BASE%/}/oradata/ssl_wallet"
SSL_WALLET_TMP="${SSL_WALLET_DIR}.new"
SSL_WALLET_BACKUP="${SSL_WALLET_DIR}.previous"
SSL_WALLET_PWD="${SSL_WALLET_PWD:-${ORACLE_PWD}}"

CWALLET="${SSL_WALLET_DIR%/}/cwallet.sso"
EWALLET="${SSL_WALLET_DIR%/}/ewallet.p12"

# The completion marker is stored inside the wallet directory so it is
# activated atomically together with the wallet it describes.
WALLET_MARKER_NAME=".local-apex-dev-wallet-complete"
WALLET_MARKER_FILE="${SSL_WALLET_DIR%/}/${WALLET_MARKER_NAME}"

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------
wallet_is_valid() {
  # Verify the required wallet files and completion marker.
  [[ -f "${CWALLET}" ]] || return 1
  [[ -f "${EWALLET}" ]] || return 1
  [[ -f "${WALLET_MARKER_FILE}" ]] || return 1
  [[ -f "${LOCAL_CA_CERT}" ]] || return 1

  # Verify password can open the wallet.
  if ! orapki wallet display -wallet "${SSL_WALLET_DIR}" -pwd "${SSL_WALLET_PWD}" &> /dev/null; then
    echo "WARNING : Existing wallet cannot be opened with the current SSL_WALLET_PWD." >&2
    return 1
  fi

  # Verify that the wallet contains the current local gateway CA certificate.
  local local_fp wallet_fp
  local temp_cert="${WORK_DIR}/existing_ca.cer"

  mkdir -p "${WORK_DIR}"
  rm -f "${temp_cert}"

  local_fp=$(openssl x509 -noout -fingerprint -sha256 -in "${LOCAL_CA_CERT}")

  if ! orapki wallet export -wallet "${SSL_WALLET_DIR}" -pwd "${SSL_WALLET_PWD}" -dn "CN=Local Docker CA" -cert "${temp_cert}" &> /dev/null; then
    echo "WARNING : Local CA certificate 'CN=Local Docker CA' not found in the existing wallet." >&2
    return 1
  fi

  wallet_fp=$(openssl x509 -noout -fingerprint -sha256 -in "${temp_cert}")

  if [[ "${local_fp}" != "${wallet_fp}" ]]; then
    echo "WARNING : The CA certificate in the wallet does not match the current ${LOCAL_CA_CERT}." >&2
    return 1
  fi

  return 0
}

# ------------------------------------------------------------------------------
# SSL Wallet and Certificate Provisioning.
# ------------------------------------------------------------------------------
if wallet_is_valid; then
  echo "INFO : Valid Oracle wallet already exists. Skipping wallet creation."
else
  echo "INFO : Oracle wallet is missing, invalid, or out of date. Recreating it."

  rm -rf "${WORK_DIR}" "${SSL_WALLET_TMP}"
  mkdir -p "${CA_CERT_DIR}" "${SSL_WALLET_TMP}"

  if [[ ! -f "${LOCAL_CA_CERT}" ]]; then
    echo "ERROR : Local gateway CA certificate was not found: ${LOCAL_CA_CERT}" >&2
    return 1
  fi

  echo "INFO : Downloading standard DBMS_CLOUD certificates..."
  curl \
    --fail \
    --location \
    --show-error \
    --silent \
    --output "${CA_CERT_ARCHIVE}" \
    "${CA_DOWNLOAD_URL}"

  echo "INFO : Extracting standard DBMS_CLOUD certificates..."
  tar -xf "${CA_CERT_ARCHIVE}" -C "${CA_CERT_DIR}"

  mapfile -t STANDARD_CERTIFICATES < <(
    find "${CA_CERT_DIR}" \
      -type f \
      -name '*.cer' \
      -print |
      sort
  )

  if (( ${#STANDARD_CERTIFICATES[@]} == 0 )); then
    echo "ERROR : The downloaded certificate archive contained no .cer files." >&2
    return 1
  fi

  CERTIFICATES=("${LOCAL_CA_CERT}" "${STANDARD_CERTIFICATES[@]}")

  echo "INFO : Creating Oracle wallet at ${SSL_WALLET_TMP}..."
  orapki wallet create \
    -wallet "${SSL_WALLET_TMP}" \
    -pwd "${SSL_WALLET_PWD}" \
    -auto_login

  echo "INFO : Importing ${#CERTIFICATES[@]} trusted certificates into the Oracle wallet..."
  for certificate in "${CERTIFICATES[@]}"; do
    # echo "INFO : Adding certificate $(basename "${certificate}") to wallet..."
    orapki wallet add \
      -wallet "${SSL_WALLET_TMP}" \
      -trusted_cert \
      -cert "${certificate}" \
      -pwd "${SSL_WALLET_PWD}" \
      > /dev/null
  done

  if [[ ! -f "${SSL_WALLET_TMP}/cwallet.sso" ||
        ! -f "${SSL_WALLET_TMP}/ewallet.p12" ]]; then
    echo "ERROR : Oracle wallet files were not created." >&2
    return 1
  fi

  echo "INFO : Validating the newly generated Oracle wallet..."

  # Confirm that the wallet can be opened with the configured password.
  if ! orapki wallet display -wallet "${SSL_WALLET_TMP}" -pwd "${SSL_WALLET_PWD}" &> /dev/null; then
    echo "ERROR : Failed to open the newly generated wallet with the provided password." >&2
    return 1
  fi

  # Export the local CA from the new wallet for validation.
  if ! orapki wallet export -wallet "${SSL_WALLET_TMP}" -pwd "${SSL_WALLET_PWD}" -dn "CN=Local Docker CA" -cert "${WORK_DIR}/extracted_ca_tmp.cer" &> /dev/null; then
    echo "ERROR : Local CA certificate 'CN=Local Docker CA' not found in the newly generated wallet." >&2
    return 1
  fi

  # Verify that the exported CA matches the current local CA certificate.
  LOCAL_CA_FP=$(openssl x509 -noout -fingerprint -sha256 -in "${LOCAL_CA_CERT}")
  WALLET_CA_FP=$(openssl x509 -noout -fingerprint -sha256 -in "${WORK_DIR}/extracted_ca_tmp.cer")

  if [[ "${LOCAL_CA_FP}" != "${WALLET_CA_FP}" ]]; then
    echo "ERROR : The CA certificate in the new wallet does not match the cryptographic fingerprint of ${LOCAL_CA_CERT}." >&2
    return 1
  fi

  echo "INFO : New Oracle wallet passed all validation checks."

  touch "${SSL_WALLET_TMP%/}/${WALLET_MARKER_NAME}"

  # Activate the new wallet only after all certificate imports and checks pass.
  rm -rf "${SSL_WALLET_BACKUP}"

  if [[ -d "${SSL_WALLET_DIR}" ]]; then
    mv "${SSL_WALLET_DIR}" "${SSL_WALLET_BACKUP}"
  fi

  if mv "${SSL_WALLET_TMP}" "${SSL_WALLET_DIR}"; then
    rm -rf "${SSL_WALLET_BACKUP}"
    echo "INFO : New Oracle wallet activated successfully."
  else
    echo "ERROR : Failed to activate the new Oracle wallet." >&2
    rm -rf "${SSL_WALLET_DIR}"

    if [[ -d "${SSL_WALLET_BACKUP}" ]]; then
      mv "${SSL_WALLET_BACKUP}" "${SSL_WALLET_DIR}"
    fi

    return 1
  fi
fi

# ------------------------------------------------------------------------------
# Database SSL_WALLET Property
# ------------------------------------------------------------------------------
echo "INFO : Configuring database property SSL_WALLET..."
sqlplus -L -S / as sysdba <<EOF_SQL
whenever oserror exit failure
whenever sqlerror exit sql.sqlcode

set serveroutput on
set heading off
set feedback off
set pagesize 0
set verify off
set trim on

@${ORACLE_HOME}/rdbms/admin/sqlsessstart.sql

begin
  if sys_context('userenv', 'con_name') = 'CDB\$ROOT' then
    execute immediate q'[alter database property set ssl_wallet = '${SSL_WALLET_DIR}']';
  end if;
end;
/

@${ORACLE_HOME}/rdbms/admin/sqlsessend.sql
exit
EOF_SQL

echo "INFO : Oracle wallet configuration completed successfully."