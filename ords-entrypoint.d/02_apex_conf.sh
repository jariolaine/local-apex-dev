#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# Oracle APEX Instance Configuration
#
# Applies APEX instance parameters and configures the INTERNAL workspace
# administrator account.
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APEX_ADMIN_USER_NAME="${APEX_ADMIN_USER_NAME:-ADMIN}"
APEX_ADMIN_USER_PWD="${APEX_ADMIN_USER_PWD:-${ORACLE_PWD}}"
APEX_ADMIN_USER_EMAIL="${APEX_ADMIN_USER_EMAIL:-}"

APEX_INSTANCE_CONF="${HOME%/}/apex_instance_parameters.yaml"
APEX_INSTANCE_SQL_FILE="${HOME%/}/apex_instance_parameters.sql"
APEX_INSTANCE_SQL_TMP="${APEX_INSTANCE_SQL_FILE}.tmp"

# Source helper functions from the common.sh file
# shellcheck source=ords-entrypoint.d/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------
cleanup() {
  rm -f -- "${APEX_INSTANCE_SQL_TMP}"
}

trap cleanup EXIT

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

if [[ -z "${ORACLE_PWD:-}" ]]; then
  error 'ORACLE_PWD is not set or is empty.'
  exit 1
fi

if ! is_apex_installed; then
  info "APEX is not installed to database. Skipping."
  exit 0
fi

if [[ ! -s "${APEX_INSTANCE_CONF}" ]]; then
  info "APEX instance configuration file ${APEX_INSTANCE_CONF} is missing or empty. Skipping."
  exit 0
fi

echo "----------------------------------------"
info "Generating APEX instance configuration..."

# Dynamically generate the PL/SQL block.
cat <<EOF_SQL > "${APEX_INSTANCE_SQL_TMP}"
whenever oserror exit failure
whenever sqlerror exit sql.sqlcode

set serveroutput on
set heading off
set feedback off
set pagesize 0
set verify off
set trim on

declare
  l_apex_installed number;
  l_create_or_update_admin_user varchar(1) := 'N';
begin

  dbms_output.put_line('----------------------------------------');

  -- Query DBA_REGISTRY to ensure the APEX component is valid and installed.
  dbms_output.put_line(
    'INFO : Checking whether APEX is installed and valid...'
  );

  select count(*) into l_apex_installed
  from dba_registry
  where comp_id = 'APEX'
    and status = 'VALID';

  if l_apex_installed = 0 then
    raise_application_error(
      -20001
    , 'APEX is not installed or is not valid.'
    );
  end if;

  dbms_output.put_line(
    'INFO : APEX is installed and valid. Applying instance parameters...'
  );

  -- Set APEX instance parameters.
EOF_SQL

# Read APEX instance configuration.
while IFS=':' read -r param_name param_value || [[ -n "$param_name" ]]; do

  # Trim the parameter name and convert it to uppercase.
  param_name="$(trim "${param_name^^}")"

  # Skip empty lines and full-line comments.
  if [[ -z "$param_name" || "$param_name" == \#* ]]; then
    continue
  fi

  if [[ "$param_name" == "---" || "$param_name" == "..." ]]; then
    continue
  fi

  # Normalize the parameter value.
  param_value="$(yaml_scalar "$param_value")"

  param_name_sql="$(sql_string "$param_name")"
  param_value_sql="$(sql_string "$param_value")"

  # Append the parameter-setting statement to the generated PL/SQL block.
  cat <<EOF_SQL >> "${APEX_INSTANCE_SQL_TMP}"
  dbms_output.put_line(
    'INFO : Setting APEX instance parameter: ' || $param_name_sql || '.'
  );
  apex_instance_admin.set_parameter(
    p_parameter => $param_name_sql
  , p_value     => $param_value_sql
  );

EOF_SQL

done < "${APEX_INSTANCE_CONF}"

admin_name_sql="$(sql_string "${APEX_ADMIN_USER_NAME^^}")"
admin_password_sql="$(sql_string "${APEX_ADMIN_USER_PWD}")"
admin_email_sql="$(sql_nullable_string "${APEX_ADMIN_USER_EMAIL}")"

cat <<EOF_SQL >> "${APEX_INSTANCE_SQL_TMP}"
  -- Check if APEX instance admin exists.
  begin
    select
      case
        when account_locked = 'Yes'
        then 'Y'
        when date_created = date_last_updated
        then 'Y'
        when DATE_LAST_LOGIN is null
        then 'Y'
        when date_last_updated > date_last_login
        then 'Y'
        else 'N'
      end
    into l_create_or_update_admin_user
    from apex_workspace_apex_users
    where workspace_name = 'INTERNAL'
      and user_name = $admin_name_sql
    ;
  exception when no_data_found then
    l_create_or_update_admin_user := 'Y';
  end;

  -- Create APEX instance admin if it does not exist,
  -- or unlock account and reset password if needed.
  if l_create_or_update_admin_user = 'Y' then

    dbms_output.put_line(
      'INFO : Creating or updating APEX instance administrator: ' ||
      $admin_name_sql || '.'
    );
    apex_instance_admin.create_or_update_admin_user(
      p_username  => $admin_name_sql
    , p_password  => $admin_password_sql
    , p_email     => $admin_email_sql
    );

  else
    dbms_output.put_line(
      'INFO : APEX instance administrator ' ||
      $admin_name_sql || ' requires no update.'
    );
  end if;

  dbms_output.put_line('----------------------------------------');

  commit;
end;
/
exit
EOF_SQL

echo "----------------------------------------"
info "Applying APEX instance configuration..."

mv -f -- "${APEX_INSTANCE_SQL_TMP}" "${APEX_INSTANCE_SQL_FILE}"

if ! run_sql "${APEX_INSTANCE_SQL_FILE}"; then
  error "APEX instance configuration failed. Review the SQLcl output above."
  exit 1
fi

info "APEX instance configuration completed successfully."
