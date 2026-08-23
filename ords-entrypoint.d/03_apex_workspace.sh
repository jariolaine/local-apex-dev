#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# Oracle APEX Workspace Configuration
#
# Provisions configured APEX workspaces, database schemas, workspace users,
# workspace parameters, REST access, and required schema privileges.
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APEX_WORKSPACE_CONF="${HOME%/}/apex_workspaces.yaml"
APEX_WORKSPACE_SQL_FILE="${HOME%/}/apex_workspaces.sql"
APEX_WORKSPACE_SQL_TMP="${APEX_WORKSPACE_SQL_FILE}.tmp"

HTTP_HOST="*"
HTTP_PORT="443"

# Source helper functions from the common.sh file
# shellcheck source=ords-entrypoint.d/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------
cleanup() {
  rm -f -- "${APEX_WORKSPACE_SQL_TMP}"
}

trap cleanup EXIT

apply_defaults() {
  local i

  if [[ -z "$ws_schema" ]]; then
    ws_schema="WKSP_${ws_name}"

    printf \
      "INFO : Schema name for workspace %s not provided. Using %s.\n" \
      "$ws_name" \
      "$ws_schema"
  fi

  if [[ -z "$ws_schema_pass" ]]; then
    ws_schema_pass="${ORACLE_PWD}"

    printf \
      "INFO : Schema password for workspace %s taken from ORACLE_PWD.\n" \
      "$ws_name"
  fi

  for ((i = 0; i < ${#users_name[@]}; i++)); do
    if [[ -z "${users_pass[$i]-}" ]]; then
      users_pass[i]="${ORACLE_PWD}"

      printf \
        "INFO : Password for user %s in workspace %s taken from ORACLE_PWD.\n" \
        "${users_name[$i]}" \
        "$ws_name"
    fi

    if [[ -z "${users_chg[$i]-}" ]]; then
      users_chg[i]="Y"
    fi
  done
}

validate_workspace() {
  local i

  if [[ -z "$ws_name" ]]; then
    error 'workspace_name is missing.'
    exit 1
  fi

  apply_defaults

  validate_identifier 'workspace name' "$ws_name"
  validate_identifier 'schema name' "$ws_schema"
  validate_schema_password "$ws_schema_pass"

  for ((i = 0; i < ${#users_name[@]}; i++)); do
    if [[ -z "${users_name[$i]-}" ]]; then
      printf \
        "ERROR : User name is missing in workspace %s.\n" \
        "$ws_name" \
        >&2
      exit 1
    fi

    if [[ -z "${users_pass[$i]-}" ]]; then
      printf \
        "ERROR : user_password is missing for user %s in workspace %s.\n" \
        "${users_name[$i]}" \
        "$ws_name" \
        >&2
      exit 1
    fi

    if [[ ! "${users_chg[$i]-}" =~ ^[YN]$ ]]; then
      printf \
        "ERROR : change_password_on_first_use for user %s must be Y or N.\n" \
        "${users_name[$i]}" \
        >&2
      exit 1
    fi
  done
}

generate_workspace_sql() {
  local i
  local ws_name_sql
  local ws_schema_sql
  local schema_password_escaped

  validate_workspace

  ws_name_sql="$(sql_string "$ws_name")"
  ws_schema_sql="$(sql_string "$ws_schema")"

  # Escape apostrophes because the password is inserted into a PL/SQL string.
  schema_password_escaped="${ws_schema_pass//\'/\'\'}"

  info "Generating SQL for workspace: $ws_name..."

  cat <<EOF_SQL >> "${APEX_WORKSPACE_SQL_TMP}"
--------------------------------------------------------
-- Setup for Workspace: $ws_name.
--------------------------------------------------------
declare
  l_apex_installed  number;
  l_workspace_exist number;
  l_schema_exist    number;
  l_tablespace      varchar2(256);
  l_workspace       varchar2(256) := dbms_assert.simple_sql_name($ws_name_sql);
  l_schema          varchar2(256) := dbms_assert.simple_sql_name($ws_schema_sql);
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
    'INFO : APEX is installed and valid.'
    || ' Checking whether workspace ' || l_workspace || ' already exists...'
  );

  select count(*) into l_workspace_exist
    from apex_workspaces
   where upper(workspace) = upper(l_workspace);

  -- Skip schema and user provisioning for an existing workspace,
  -- then continue with workspace parameter configuration.
  if l_workspace_exist > 0 then
    dbms_output.put_line(
      'INFO : Workspace ' || l_workspace || ' already exists.'
      || ' Skipping schema and user provisioning;'
      || ' applying workspace parameters.'
    );
    goto workspace_parameters;
  end if;

  dbms_output.put_line(
    'INFO : Workspace does not exist. Checking whether schema ' || l_schema || ' already exists...'
  );

  -- Create the workspace schema when it does not already exist.
  select count(*) into l_schema_exist
    from dba_users
   where username = l_schema;

  if l_schema_exist = 0 then

    dbms_output.put_line(
      'INFO : Schema does not exist. Creating schema: ' || l_schema || '.'
    );

    -- Create workspace parsing schema.
    execute immediate
      'create user ' || l_schema ||
      ' identified by "$schema_password_escaped" account unlock';

    -- Grant privileges.
    dbms_output.put_line(
      'INFO : Granting privileges to schema: ' || l_schema || '.'
    );

    execute immediate
      'grant connect, resource, db_developer_role, cloud_user_role to ' || l_schema;

    for c1 in (
      select privilege
        from dba_sys_privs
       where grantee = 'APEX_GRANTS_FOR_NEW_USERS_ROLE'
       order by privilege
    ) loop
      execute immediate
        'grant ' || c1.privilege || ' to ' || l_schema;
    end loop;

    -- Grant quota on the user default tablespace.
    select default_tablespace
      into l_tablespace
      from dba_users
     where username = l_schema;

    dbms_output.put_line(
      'INFO : Granting unlimited quota on tablespace ' ||
      l_tablespace || ' to schema ' || l_schema  || '.'
    );

    execute immediate
      'alter user ' || l_schema ||
      ' default role all quota unlimited on ' || l_tablespace;

    -- REST enable schema.
    dbms_output.put_line(
      'INFO : Enabling ORDS REST access for schema ' || l_schema || '.'
    );

    ords_admin.enable_schema(
      p_schema          => l_schema
    , p_auto_rest_auth  => true
    );

    dbms_output.put_line(
      'INFO : Granting HTTPS network access to schema ' || l_schema || '.'
    );

    -- Grant HTTPS network access to the schema.
    dbms_network_acl_admin.append_host_ace(
      host        => '${HTTP_HOST}'
    , lower_port  => ${HTTP_PORT}
    , upper_port  => ${HTTP_PORT}
    , ace         =>
        xs\$ace_type(
          privilege_list => xs\$name_list('http', 'http_proxy')
        , principal_name => l_schema
        , principal_type => xs_acl.ptype_db
        )
    );

  else
    dbms_output.put_line(
      'INFO : Schema ' || l_schema || ' already exists. Using it for the new workspace.'
    );
  end if;

  -- Create workspace.
  dbms_output.put_line(
    'INFO : Creating workspace: ' || l_workspace || '.'
  );

  apex_instance_admin.add_workspace(
    p_workspace      => l_workspace,
    p_primary_schema => l_schema
  );

  -- Set APEX workspace.
  apex_util.set_workspace(
    p_workspace => l_workspace
  );

EOF_SQL

  for ((i = 0; i < ${#users_name[@]}; i++)); do
    local u_name_sql
    local u_pass_sql
    local u_desc_sql
    local u_email_sql
    local u_chg_sql
    local u_privs_sql

    u_name_sql="$(sql_string "${users_name[$i]}")"
    u_pass_sql="$(sql_string "${users_pass[$i]}")"
    u_desc_sql="$(sql_nullable_string "${users_desc[$i]-}")"
    u_email_sql="$(sql_nullable_string "${users_email[$i]-}")"
    u_chg_sql="$(sql_string "${users_chg[$i]}")"
    u_privs_sql="$(sql_nullable_string "${users_privs[$i]-}")"

    cat <<EOF_SQL >> "${APEX_WORKSPACE_SQL_TMP}"
  -- Create workspace user.
  dbms_output.put_line(
    'INFO : Creating APEX user: ' || $u_name_sql || ' in ' || l_workspace || '.'
  );

  apex_util.create_user(
    p_user_name                    => $u_name_sql
  , p_web_password                 => $u_pass_sql
  , p_description                  => $u_desc_sql
  , p_email_address                => $u_email_sql
  , p_developer_privs              => $u_privs_sql
  , p_change_password_on_first_use => $u_chg_sql
  , p_default_schema               => l_schema
  );

EOF_SQL
  done

  cat <<EOF_SQL >> "${APEX_WORKSPACE_SQL_TMP}"
  -- Set workspace parameters.
  <<workspace_parameters>>

  -- Set APEX workspace.
  apex_util.set_workspace(
    p_workspace => l_workspace
  );

EOF_SQL

  for ((i = 0; i < ${#params_key[@]}; i++)); do
    local param_name_sql
    local param_value_sql

    param_name_sql="$(sql_string "${params_key[$i]}")"
    param_value_sql="$(sql_string "${params_val[$i]}")"

    cat <<EOF_SQL >> "${APEX_WORKSPACE_SQL_TMP}"
  dbms_output.put_line(
    'INFO : Setting workspace parameter: ' || $param_name_sql || '.'
  );

  apex_instance_admin.set_workspace_parameter(
    p_workspace => l_workspace,
    p_parameter => $param_name_sql,
    p_value     => $param_value_sql
  );

EOF_SQL
  done

  cat <<EOF_SQL >> "${APEX_WORKSPACE_SQL_TMP}"

  dbms_output.put_line(
    'INFO : Finished configuring workspace ' || l_workspace || '.'
  );
  dbms_output.put_line('----------------------------------------');

  commit;
end;
/
EOF_SQL

((ws_count += 1))
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

ws_name=""
ws_schema=""
ws_schema_pass=""
ws_count=0

users_name=()
users_pass=()
users_desc=()
users_email=()
users_chg=()
users_privs=()

params_key=()
params_val=()

in_section=""
user_idx=-1

if ! is_apex_installed; then
  info "APEX is not installed to database. Skipping."
  exit 0
fi

if [[ ! -f "${APEX_WORKSPACE_CONF}" ]]; then
  info "Workspaces configuration file ${APEX_WORKSPACE_CONF} not found."
  exit 0
fi

echo "----------------------------------------"
info "Generating APEX workspace configuration..."

# Dynamically generate the PL/SQL block
cat <<'EOF_SQL' > "${APEX_WORKSPACE_SQL_TMP}"
whenever oserror exit failure
whenever sqlerror exit sql.sqlcode

set serveroutput on
set heading off
set feedback off
set pagesize 0
set verify off
set trim on

EOF_SQL

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  line="${raw_line//$'\r'/}"

  [[ -z "$(trim "$line")" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ "$(trim "$line")" == "---" ]] && continue
  [[ "$(trim "$line")" == "..." ]] && continue

  if [[ "$line" =~ ^[[:space:]]*workspaces:[[:space:]]*$ ]]; then
    continue
  fi

  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*workspace_name:[[:space:]]*(.*)$ ]]; then
    new_ws_name_raw="${BASH_REMATCH[1]}"

    if [[ -n "$ws_name" ]]; then
      generate_workspace_sql
    fi

    ws_name="$(yaml_scalar "$new_ws_name_raw")"
    ws_name="${ws_name^^}"

    ws_schema=""
    ws_schema_pass=""

    users_name=()
    users_pass=()
    users_desc=()
    users_email=()
    users_chg=()
    users_privs=()

    params_key=()
    params_val=()

    in_section="workspace"
    user_idx=-1

    continue
  fi

  if [[ "$in_section" == "workspace" ]]; then
    if [[ "$line" =~ ^[[:space:]]*schema_name:[[:space:]]*(.*)$ ]]; then
      ws_schema="$(yaml_scalar "${BASH_REMATCH[1]}")"
      ws_schema="${ws_schema^^}"
      continue
    fi

    if [[ "$line" =~ ^[[:space:]]*schema_password:[[:space:]]*(.*)$ ]]; then
      ws_schema_pass="$(yaml_scalar "${BASH_REMATCH[1]}")"
      continue
    fi
  fi

  if [[ "$line" =~ ^[[:space:]]*workspace_users:[[:space:]]*$ ]]; then
    in_section="users"
    continue
  fi

  if [[ "$line" =~ ^[[:space:]]*workspace_parameters:[[:space:]]*$ ]]; then
    in_section="params"
    continue
  fi

  if [[ "$in_section" == "users" ]]; then
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*user_name:[[:space:]]*(.*)$ ]]; then
      user_idx=$((user_idx + 1))

      users_name[user_idx]="$(yaml_scalar "${BASH_REMATCH[1]}")"
      users_name[user_idx]="${users_name[$user_idx]^^}"

      # Default when omitted.
      users_chg[user_idx]="Y"

      continue
    fi

    if (( user_idx < 0 )); then
      error 'User property found before user_name:'
      echo "  $raw_line" >&2
      exit 1
    fi

    if [[ "$line" =~ ^[[:space:]]*user_email:[[:space:]]*(.*)$ ]]; then
      users_email[user_idx]="$(yaml_scalar "${BASH_REMATCH[1]}")"
      continue
    fi

    if [[ "$line" =~ ^[[:space:]]*user_description:[[:space:]]*(.*)$ ]]; then
      users_desc[user_idx]="$(yaml_scalar "${BASH_REMATCH[1]}")"
      continue
    fi

    if [[ "$line" =~ ^[[:space:]]*user_password:[[:space:]]*(.*)$ ]]; then
      users_pass[user_idx]="$(yaml_scalar "${BASH_REMATCH[1]}")"
      continue
    fi

    if [[ "$line" =~ ^[[:space:]]*change_password_on_first_use:[[:space:]]*(.*)$ ]]; then
      users_chg[user_idx]="$(yaml_scalar "${BASH_REMATCH[1]}")"
      users_chg[user_idx]="${users_chg[$user_idx]^^}"

      # An explicitly empty value also defaults to Y.
      if [[ -z "${users_chg[$user_idx]}" ]]; then
        users_chg[user_idx]="Y"
      fi

      continue
    fi

    if [[ "$line" =~ ^[[:space:]]*developer_privs:[[:space:]]*(.*)$ ]]; then
      users_privs[user_idx]="$(yaml_scalar "${BASH_REMATCH[1]}")"
      continue
    fi

  fi

  if [[ "$in_section" == "params" ]]; then
    if [[ "$line" =~ ^[[:space:]]*([A-Za-z0-9_]+):[[:space:]]*(.*)$ ]]; then
      key="${BASH_REMATCH[1]^^}"
      val="$(yaml_scalar "${BASH_REMATCH[2]}")"

      params_key+=("$key")
      params_val+=("$val")

      continue
    fi
  fi

  error 'Unsupported or misplaced configuration line:'
  echo "  $raw_line" >&2
  echo 'Use the structure shown in the example configuration.' >&2
  exit 1
done < "${APEX_WORKSPACE_CONF}"

if [[ -n "$ws_name" ]]; then
  generate_workspace_sql
fi

cat <<'EOF_SQL' >> "${APEX_WORKSPACE_SQL_TMP}"
exit;
EOF_SQL

mv -f -- "${APEX_WORKSPACE_SQL_TMP}" "${APEX_WORKSPACE_SQL_FILE}"

echo "----------------------------------------"
if (( ws_count == 0 )); then
  info "No APEX workspaces are defined. Nothing to provision."
  echo "----------------------------------------"
  exit 0
fi
info "Applying APEX workspace configuration..."

if ! run_sql "${APEX_WORKSPACE_SQL_FILE}"; then
  error "APEX workspace configuration failed. Review the SQLcl output above."
  exit 1
fi

info "APEX workspace configuration completed successfully."
echo "----------------------------------------"
