#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# DBMS_CLOUD Installation and Configuration
#
# Validates and installs the required DBMS_CLOUD packages, configures the
# database network ACL, and provisions CLOUD_USER_ROLE in the target PDB.
# ==============================================================================

# ------------------------------------------------------------------------------
# Configuration Variables
# ------------------------------------------------------------------------------
# Store the Oracle software version for which DBMS_CLOUD was last validated.
# A version change triggers Oracle's idempotent DBMS_CLOUD installation again.
DBMS_CLOUD_STATE_DIR="${ORACLE_BASE%/}/oradata/.local-apex-dev"
DBMS_CLOUD_VER_FILE="${DBMS_CLOUD_STATE_DIR}/dbms_cloud_version"

DBMS_CLOUD_LOG_DIR="/tmp/dbms-cloud-install"
DBMS_CLOUD_INSTALLED_VER=""
DBMS_CLOUD_VER_FILE_TMP="${DBMS_CLOUD_VER_FILE}.tmp"

ORACLE_PWD="${ORACLE_PWD:-}"
ORACLE_PDB="${ORACLE_PDB:-FREEPDB1}"
CLOUD_USER="C##CLOUD\$SERVICE"
CLOUD_ROLE="CLOUD_USER_ROLE"
HTTP_HOST="*"
HTTP_PORT="443"

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------

# Validate the required DBMS_CLOUD packages in CDB$ROOT and the target PDB.
dbms_cloud_validation_result() {

  sqlplus -L -S / as sysdba <<EOF_SQL | tr -d '[:space:]'
whenever oserror exit failure
whenever sqlerror exit sql.sqlcode

set heading off
set feedback off
set pagesize 0
set verify off
set trimspool on

with expected_packages (object_name) as (
  select 'DBMS_CLOUD'               from dual union all
  select 'DBMS_CLOUD_PIPELINE'      from dual union all
  select 'DBMS_CLOUD_REPO'          from dual union all
  select 'DBMS_CLOUD_NOTIFICATION'  from dual union all
  select 'DBMS_CLOUD_AI'            from dual union all
  select 'DBMS_CLOUD_AI_AGENT'      from dual
),
expected_types (object_type) as (
  select 'PACKAGE'      from dual union all
  select 'PACKAGE BODY' from dual
),
expected_containers (con_id) as (
  select con_id
  from v\$containers
  where name in ('CDB\$ROOT', upper('${ORACLE_PDB}'))
),
missing_objects as (
  select
    c.con_id,
    p.object_name,
    t.object_type
  from expected_containers c
  cross join expected_packages p
  cross join expected_types t
  minus
  select
    o.con_id,
    o.object_name,
    o.object_type
  from cdb_objects o
  where o.owner = upper('${CLOUD_USER}')
    and o.status = 'VALID'
)
select case
        when count(*) = 0 then 1
        else 0
      end
from missing_objects;

exit
EOF_SQL
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

# Initialize directories.
mkdir -p "${DBMS_CLOUD_STATE_DIR}"
rm -rf "${DBMS_CLOUD_LOG_DIR}"
mkdir -p "${DBMS_CLOUD_LOG_DIR}"

# Read the current Oracle software version.
if [[ ! -x "${ORACLE_HOME}/bin/oraversion" ]]; then
  echo "ERROR : ${ORACLE_HOME}/bin/oraversion was not found." >&2
  return 1
fi

# Check database version.
DB_SOFTWARE_VERSION="$(
  "${ORACLE_HOME}/bin/oraversion" -compositeVersion |
    tr -d '[:space:]'
)"

if [[ -z "$DB_SOFTWARE_VERSION" ]]; then
  echo "ERROR : Could not determine the Oracle software version." >&2
  return 1
fi

# Read the previously recorded DBMS_CLOUD version, if available.
if [[ -f "${DBMS_CLOUD_VER_FILE}" ]]; then
  DBMS_CLOUD_INSTALLED_VER="$(
    tr -d '[:space:]' < "${DBMS_CLOUD_VER_FILE}"
  )"
fi


# Validate DBMS_CLOUD packages in database.
if ! DBMS_CLOUD_VALID="$(dbms_cloud_validation_result)"; then
  echo "ERROR : Failed to validate DBMS_CLOUD installation." >&2
  return 1
fi
INSTALL_DBMS_CLOUD=false

case "${DBMS_CLOUD_VALID}" in
  1)
    if [[ "${DBMS_CLOUD_INSTALLED_VER}" != "$DB_SOFTWARE_VERSION" ]]; then
      if [[ -z "${DBMS_CLOUD_INSTALLED_VER}" ]]; then
        echo "INFO : DBMS_CLOUD version marker is missing. Rerunning DBMS_CLOUD installation."
      else
        echo "INFO : Oracle software version changed from ${DBMS_CLOUD_INSTALLED_VER} to ${DB_SOFTWARE_VERSION}."
      fi
      INSTALL_DBMS_CLOUD=true
    else
      echo "INFO : DBMS_CLOUD is installed and valid for Oracle version ${DB_SOFTWARE_VERSION}."
    fi
    ;;

  0)
    echo "INFO : DBMS_CLOUD is missing or invalid."
    INSTALL_DBMS_CLOUD=true
    ;;

  *)
    echo "ERROR : Unexpected DBMS_CLOUD validation result: ${DBMS_CLOUD_VALID}" >&2
    return 1
    ;;
esac

# ------------------------------------------------------------------------------
# DBMS_CLOUD Package Installation
# ------------------------------------------------------------------------------
if [[ "$INSTALL_DBMS_CLOUD" == true ]]; then

  echo "INFO : Installing or updating DBMS_CLOUD..."

  if ! "${ORACLE_HOME}/perl/bin/perl" "${ORACLE_HOME}/rdbms/admin/catcon.pl" \
    -u sys/"${ORACLE_PWD}" \
    --force_pdb_mode 'READ WRITE' \
    -b catclouduser_install \
    -d "${ORACLE_HOME}/rdbms/admin/" \
    -l "${DBMS_CLOUD_LOG_DIR}" \
    catclouduser.sql; then
    echo "ERROR : catclouduser.sql failed." >&2
    find "$DBMS_CLOUD_LOG_DIR" -maxdepth 1 -type f -print
    return 1
  fi

  if ! "${ORACLE_HOME}/perl/bin/perl" "${ORACLE_HOME}/rdbms/admin/catcon.pl" \
    -u sys/"${ORACLE_PWD}" \
    --force_pdb_mode 'READ WRITE' \
    -b dbms_cloud_install \
    -d "${ORACLE_HOME}/rdbms/admin/" \
    -l "${DBMS_CLOUD_LOG_DIR}" \
    dbms_cloud_install.sql; then
    echo "ERROR : dbms_cloud_install.sql failed." >&2
    find "$DBMS_CLOUD_LOG_DIR" -maxdepth 1 -type f -print
    return 1
  fi

fi

# Validate DBMS_CLOUD packages in database.
DBMS_CLOUD_VALID="$(dbms_cloud_validation_result)"

if [[ "$DBMS_CLOUD_VALID" != "1" ]]; then
  echo "ERROR : DBMS_CLOUD installation validation failed." >&2
  echo "ERROR : Review the catcon.pl logs in ${DBMS_CLOUD_LOG_DIR}." >&2

  find "${DBMS_CLOUD_LOG_DIR}" \
    -maxdepth 1 \
    -type f \
    -print

  return 1
fi

printf '%s\n' "$DB_SOFTWARE_VERSION" > "${DBMS_CLOUD_VER_FILE_TMP}"
mv -f "${DBMS_CLOUD_VER_FILE_TMP}" "${DBMS_CLOUD_VER_FILE}"

echo "INFO : DBMS_CLOUD is valid for Oracle version ${DB_SOFTWARE_VERSION}."

# ------------------------------------------------------------------------------
# DBMS_CLOUD Network Access
# ------------------------------------------------------------------------------
echo "INFO : Configuring DBMS_CLOUD network access in the CDB..."
sqlplus -L -S / as sysdba << EOF_SQL
whenever oserror exit failure
whenever sqlerror exit sql.sqlcode

set serveroutput on
set heading off
set feedback off
set pagesize 0
set verify off
set trim on

@${ORACLE_HOME}/rdbms/admin/sqlsessstart.sql
-- Add an HTTPS host ACE for the DBMS_CLOUD common user.
begin
  dbms_network_acl_admin.append_host_ace(
    host       => '${HTTP_HOST}'
  , lower_port => ${HTTP_PORT}
  , upper_port => ${HTTP_PORT}
  , ace        =>
      xs\$ace_type(
        privilege_list => xs\$name_list('http', 'http_proxy')
      , principal_type => xs_acl.ptype_db
      , principal_name => '${CLOUD_USER}'
      )
  );
end;
/
commit;
@${ORACLE_HOME}/rdbms/admin/sqlsessend.sql
exit
EOF_SQL
echo "INFO : DBMS_CLOUD CDB network ACL configured successfully."

# Create the role in the PDB and grant package privileges.
echo "INFO : Configuring ${CLOUD_ROLE} in PDB ${ORACLE_PDB}..."
sqlplus -L -S / as sysdba << EOF_SQL
whenever oserror exit failure
whenever sqlerror exit sql.sqlcode

prompt INFO : Switching session container to ${ORACLE_PDB}...
alter session set container = ${ORACLE_PDB};

set serveroutput on
set heading off
set feedback off
set pagesize 0
set verify off
set trim on

declare
  l_role_exist number;
begin

  dbms_output.put_line(
    'INFO : Checking whether role ${CLOUD_ROLE} exists...'
  );
  -- Check whether ${CLOUD_ROLE} exists.
  select count(*) into l_role_exist
  from dba_roles
  where role = '${CLOUD_ROLE}'
  ;

  if l_role_exist = 0 then
    dbms_output.put_line(
      'INFO : Role ${CLOUD_ROLE} does not exist. Creating role...'
    );
    -- Create ${CLOUD_ROLE}.
    execute immediate 'create role ${CLOUD_ROLE}';

  else
    dbms_output.put_line(
      'INFO : Role ${CLOUD_ROLE} already exists. Skipping.'
    );
  end if;

  dbms_output.put_line(
    'INFO : Granting DBMS_CLOUD package privileges to ${CLOUD_ROLE}...'
  );
  -- Grant execute privileges on DBMS_CLOUD packages to ${CLOUD_ROLE}.
  execute immediate 'grant execute on dbms_cloud to ${CLOUD_ROLE}';
  execute immediate 'grant execute on dbms_cloud_pipeline to ${CLOUD_ROLE}';
  execute immediate 'grant execute on dbms_cloud_repo to ${CLOUD_ROLE}';
  execute immediate 'grant execute on dbms_cloud_notification to ${CLOUD_ROLE}';
  execute immediate 'grant execute on dbms_cloud_ai to ${CLOUD_ROLE}';
  execute immediate 'grant execute on dbms_cloud_ai_agent to ${CLOUD_ROLE}';
end;
/
commit;
exit
EOF_SQL

echo "INFO : DBMS_CLOUD setup completed successfully."
