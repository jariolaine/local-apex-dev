#!/bin/bash
set -Eeuo pipefail

# ==============================================================================
# Oracle APEX Configuration
#
# Automates the initial setup of APEX instance.
# ==============================================================================

# Construct the SQLcl connection string.
# Uses CONN_STRING if provided; otherwise, falls back to DBHOST:DBPORT/DBSERVICENAME.
SQL_CLI_CONNECTION="sys/\"${ORACLE_PWD}\"@${CONN_STRING:-${DBHOST}:${DBPORT}/${DBSERVICENAME}} as sysdba"

APEX_ADMIN_USER_NAME="${APEX_ADMIN_USER_NAME:-ADMIN}"
APEX_ADMIN_USER_PWD="${APEX_ADMIN_USER_PWD:-${ORACLE_PWD}}"
APEX_ADMIN_USER_EMAIL="${APEX_ADMIN_USER_EMAIL}"
APEX_INSTANCE_CONFIG="${HOME%/}/apex_instance_parameters.yaml"
SQL_FILE="${HOME%/}/apex_instance_parameters.sql"
SQL_TMP="${SQL_FILE}.tmp"

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------
cleanup() {
  rm -f -- "$SQL_TMP"
}

trap cleanup EXIT

trim() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"

  printf '%s' "$value"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

if [ ! -s "${APEX_INSTANCE_CONFIG}" ]; then
  echo "INFO : APEX instance configuration file ${APEX_INSTANCE_CONFIG} not found. Skipping."
  exit 0
fi

# Dynamically generate the PL/SQL block
cat <<'EOF_SQL' > "$SQL_TMP"
set serveroutput on
set define off
set verify off

declare
  l_count number;
  l_create_or_update_admin_user varchar(1) := 'N';
begin

  -- Query DBA_REGISTRY to ensure the APEX component is valid and installed.
  dbms_output.put_line(
    'INFO : Checking if APEX is installed.'
  );

  select count(*) into l_count
  from dba_registry
  where comp_id = 'APEX';

  if l_count != 1 then
    dbms_output.put_line(
      'WARNING : APEX not found in the database or is not valid. Skipping.'
    );
    return;
  end if;

  dbms_output.put_line(
    'INFO : APEX found in the database. Applying instance configurations...'
  );

EOF_SQL


cat <<EOF_SQL >> "$SQL_TMP"
  -- Set APEX instance parameters.
EOF_SQL

# Read APEX instance configuration
while IFS=':' read -r param_name param_value; do

  # Strip inline comments from the value (removes everything after '#')
  param_value="${param_value%%#*}"

  # Trim leading and trailing whitespace from the KEY and convert uppercase
  param_name="$(trim "${param_name^^}")"

  # Skip empty lines and lines that start with '#' (Comments)
  if [[ -z "$param_name" || "$param_name" == \#* ]]; then
    continue
  fi

  # Trim leading and trailing whitespace from the VALUE
  param_value="$(trim "$param_value")"

  # Append the command to our PL/SQL block
  cat <<EOF_SQL >> "$SQL_TMP"
  dbms_output.put_line(
    'Setting APEX instance parameter: $param_name = $param_value'
  );
  apex_instance_admin.set_parameter(
    p_parameter => '${param_name}'
  , p_value     => '${param_value}'
  );

EOF_SQL

done < "${APEX_INSTANCE_CONFIG}"

cat <<EOF_SQL >> "$SQL_TMP"
  -- Check does APEX instance admin exist
  begin
    select
      case
        when date_created = date_last_updated or account_locked = 'Yes'
        then 'Y'
        else 'N'
      end
    into l_create_or_update_admin_user
    from apex_workspace_apex_users
    where workspace_name = 'INTERNAL'
      and user_name = '${APEX_ADMIN_USER_NAME}'
    ;
  exception when no_data_found then
    l_create_or_update_admin_user := 'Y';
  end;

  -- Create APEX instance admin if not exist or
  -- unlock account and reset password if needed.
  if l_create_or_update_admin_user = 'Y' then
    apex_instance_admin.create_or_update_admin_user(
      p_username  => '${APEX_ADMIN_USER_NAME}'
    , p_password  => '${APEX_ADMIN_USER_PWD}'
    , p_email     => '${APEX_ADMIN_USER_EMAIL}'
    );
  end if;

  commit;
end;
/
exit
EOF_SQL

echo "INFO : Apply configuration parameters..."

mv -f -- "$SQL_TMP" "$SQL_FILE"
trap - EXIT

DEBUG= sql -S -L ${SQL_CLI_CONNECTION} @${SQL_FILE}
if [ -z "${?:-1}" ]; then
  echo "ERROR: Database connection failed. Aborting."
  exit 1
fi

echo "INFO : APEX configuration completed successfully."
