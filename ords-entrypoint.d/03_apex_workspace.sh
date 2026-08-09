#!/bin/bash
set -Eeuo pipefail

# ==============================================================================
# Oracle APEX Workspace Creation
#
# Automates the APEX workspace creation.
# ==============================================================================

# Construct the SQLcl connection string.
# Uses CONN_STRING if provided; otherwise, falls back to DBHOST:DBPORT/DBSERVICENAME.
SQL_CLI_CONNECTION="sys/\"${ORACLE_PWD}\"@${CONN_STRING:-${DBHOST}:${DBPORT}/${DBSERVICENAME}} as sysdba"

CONFIG_FILE="${HOME%/}/apex_workspaces.yaml"
SQL_FILE="${HOME%/}/apex_workspaces.sql"
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

yaml_scalar() {
  local value
  value="$(trim "$1")"

  if (( ${#value} >= 2 )); then
    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:${#value}-2}"

      # In YAML single-quoted strings, two apostrophes represent one.
      value="${value//\'\'/\'}"
    fi
  fi

  printf '%s' "$value"
}

sql_string() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf "'%s'" "$value"
}

sql_nullable_string() {
  local value="$1"

  if [[ -z "$value" ]]; then
    printf 'null'
  else
    sql_string "$value"
  fi
}

validate_identifier() {
  local label="$1"
  local value="$2"

  if [[ ! "$value" =~ ^[A-Z][A-Z0-9_\$#]*$ ]]; then
    printf "ERROR: Invalid %s '%s'.\n" "$label" "$value" >&2
    echo 'Use letters, numbers, _, $ or #, starting with a letter.' >&2
    exit 1
  fi
}

validate_schema_password() {
  local password="$1"

  if [[ "$password" == *'"'* ]]; then
    echo 'ERROR: schema_password cannot contain a double quote (").' >&2
    exit 1
  fi

  if [[ "$password" == *$'\n'* || "$password" == *$'\r'* ]]; then
    echo 'ERROR: schema_password cannot contain line breaks.' >&2
    exit 1
  fi
}

require_oracle_pwd() {
  if [[ -z "${ORACLE_PWD:-}" ]]; then
    echo \
      'ERROR: A password is missing from the configuration and ORACLE_PWD is not set or is empty.' \
      >&2
    exit 1
  fi
}

apply_defaults() {
  local i

  if [[ -z "$ws_schema" ]]; then
    ws_schema="WKSP_${ws_name}"

    printf \
      "INFO : schema_name for workspace %s not provided. Using %s.\n" \
      "$ws_name" \
      "$ws_schema"
  fi

  if [[ -z "$ws_schema_pass" ]]; then
    require_oracle_pwd
    ws_schema_pass="$ORACLE_PWD"

    printf \
      "INFO : schema_password for workspace %s taken from ORACLE_PWD.\n" \
      "$ws_name"
  fi

  for ((i = 0; i < ${#users_name[@]}; i++)); do
    if [[ -z "${users_pass[$i]-}" ]]; then
      require_oracle_pwd
      users_pass[$i]="$ORACLE_PWD"

      printf \
        "INFO : user_password for user %s in workspace %s taken from ORACLE_PWD.\n" \
        "${users_name[$i]}" \
        "$ws_name"
    fi

    if [[ -z "${users_chg[$i]-}" ]]; then
      users_chg[$i]="Y"
    fi
  done
}

validate_workspace() {
  local i

  if [[ -z "$ws_name" ]]; then
    echo 'ERROR: workspace_name is missing.' >&2
    exit 1
  fi

  apply_defaults

  validate_identifier 'workspace name' "$ws_name"
  validate_identifier 'schema name' "$ws_schema"
  validate_schema_password "$ws_schema_pass"

  for ((i = 0; i < ${#users_name[@]}; i++)); do
    if [[ -z "${users_name[$i]-}" ]]; then
      printf \
        "ERROR: user_name is missing in workspace %s.\n" \
        "$ws_name" \
        >&2
      exit 1
    fi

    if [[ -z "${users_pass[$i]-}" ]]; then
      printf \
        "ERROR: user_password is missing for user %s in workspace %s.\n" \
        "${users_name[$i]}" \
        "$ws_name" \
        >&2
      exit 1
    fi

    if [[ ! "${users_chg[$i]-}" =~ ^[YN]$ ]]; then
      printf \
        "ERROR: change_password_on_first_use for user %s must be Y or N.\n" \
        "${users_name[$i]}" \
        >&2
      exit 1
    fi
  done
}

generate_sql() {
  local i
  local ws_name_sql
  local ws_schema_sql
  local schema_password_escaped

  validate_workspace

  ws_name_sql="$(sql_string "$ws_name")"
  ws_schema_sql="$(sql_string "$ws_schema")"

  # Escape apostrophes because the password is inserted into a PL/SQL string.
  schema_password_escaped="${ws_schema_pass//\'/\'\'}"

  echo "INFO : Generating SQL for workspace: $ws_name..."

  cat <<EOF_SQL >> "$SQL_TMP"
--------------------------------------------------------
-- Setup for Workspace: $ws_name
--------------------------------------------------------
declare
  l_count       number;
  l_tablespace  varchar2(256);
  l_workspace   varchar2(256) := dbms_assert.simple_sql_name($ws_name_sql);
  l_schema      varchar2(256) := dbms_assert.simple_sql_name($ws_schema_sql);
begin

  dbms_output.put_line('----------------------------------------');

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

  -- Check if workspace already exist.
  select count(*) into l_count
    from apex_workspaces
   where upper(workspace) = upper(l_workspace);

  -- Skip the complete configuration when the workspace already exists.
  if l_count > 0 then
    dbms_output.put_line(
      'INFO : Workspace ' || l_workspace || ' already exists. Skipping...'
    );
    return;
  end if;

  -- Create the workspace schema when it does not already exist.
  select count(*) into l_count
    from dba_users
   where username = l_schema;

  if l_count = 0 then
    -- Create workspace parsing schema.
    dbms_output.put_line(
      'INFO : Creating schema: ' || l_schema)
    ;

    execute immediate
      'INFO : create user ' || l_schema ||
      ' identified by "$schema_password_escaped" account unlock';

    -- Grant privileges.
    dbms_output.put_line(
      'INFO : Granting privileges to schema: ' || l_schema
    );

    execute immediate
      'grant connect, resource to ' || l_schema;

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
      l_tablespace ||
      ' to schema ' ||
      l_schema
    );

    execute immediate
      'alter user ' || l_schema ||
      ' quota unlimited on ' || l_tablespace;

    -- REST enable schema
    dbms_output.put_line(
      'INFO : REST enabling the schema ' || l_schema
    );

    ords_admin.enable_schema
      p_schema          => l_schema
    , p_auto_rest_auth  => true
    );

  else
    dbms_output.put_line(
      'WARNING : Schema ' || l_schema || ' already exists. Using existing schema.'
    );
  end if;

  -- Create workspace.
  dbms_output.put_line(
    'INFO : Creating workspace: ' || l_workspace
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
    local u_email_sql
    local u_desc_sql
    local u_chg_sql

    u_name_sql="$(sql_string "${users_name[$i]}")"
    u_pass_sql="$(sql_string "${users_pass[$i]}")"
    u_email_sql="$(sql_nullable_string "${users_email[$i]-}")"
    u_desc_sql="$(sql_nullable_string "${users_desc[$i]-}")"
    u_chg_sql="$(sql_string "${users_chg[$i]}")"

    cat <<EOF_SQL >> "$SQL_TMP"
  -- Create workspace ADMIN user
  dbms_output.put_line(
    'INFO : Creating APEX user: ' || $u_name_sql || ' in ' || l_workspace
  );

  apex_util.create_user(
    p_user_name                    => $u_name_sql,
    p_email_address                => $u_email_sql,
    p_description                  => $u_desc_sql,
    p_web_password                 => $u_pass_sql,
    p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
    p_default_schema               => l_schema,
    p_change_password_on_first_use => $u_chg_sql
  );

  -- Set workspace parameters
EOF_SQL
  done

  for ((i = 0; i < ${#params_key[@]}; i++)); do
    local p_key_sql
    local p_val_sql

    p_key_sql="$(sql_string "${params_key[$i]}")"
    p_val_sql="$(sql_string "${params_val[$i]}")"

    cat <<EOF_SQL >> "$SQL_TMP"
  dbms_output.put_line(
    'INFO : Setting workspace parameter: ' ||
    $p_key_sql || ' = ' || $p_val_sql
  );

  apex_instance_admin.set_workspace_parameter(
    p_workspace => l_workspace,
    p_parameter => $p_key_sql,
    p_value     => $p_val_sql
  );

EOF_SQL
  done

  cat <<EOF_SQL >> "$SQL_TMP"
  commit;

  dbms_output.put_line(
    'Finished configuring workspace ' || l_workspace || '.'
  );
end;
/
EOF_SQL
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
ws_name=""
ws_schema=""
ws_schema_pass=""

users_name=()
users_email=()
users_desc=()
users_pass=()
users_chg=()

params_key=()
params_val=()

in_section=""
user_idx=-1

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "INFO : Workspaces configuration file $CONFIG_FILE not found."
  exit 0
fi

# Dynamically generate the PL/SQL block
cat <<'EOF_SQL' > "$SQL_TMP"
set serveroutput on
set define off
set verify off

EOF_SQL

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  line="${raw_line//$'\r'/}"

  [[ -z "$(trim "$line")" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue

  if [[ "$line" =~ ^[[:space:]]*workspaces:[[:space:]]*$ ]]; then
    continue
  fi

  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*workspace_name:[[:space:]]*(.*)$ ]]; then
    new_ws_name_raw="${BASH_REMATCH[1]}"

    if [[ -n "$ws_name" ]]; then
      generate_sql
    fi

    ws_name="$(yaml_scalar "$new_ws_name_raw")"
    ws_name="${ws_name^^}"

    ws_schema=""
    ws_schema_pass=""

    users_name=()
    users_email=()
    users_desc=()
    users_pass=()
    users_chg=()

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

      users_name[$user_idx]="$(yaml_scalar "${BASH_REMATCH[1]}")"
      users_name[$user_idx]="${users_name[$user_idx]^^}"

      # Default when omitted.
      users_chg[$user_idx]="Y"

      continue
    fi

    if (( user_idx < 0 )); then
      echo 'ERROR: User property found before user_name:' >&2
      echo "  $raw_line" >&2
      exit 1
    fi

    if [[ "$line" =~ ^[[:space:]]*user_email:[[:space:]]*(.*)$ ]]; then
      users_email[$user_idx]="$(yaml_scalar "${BASH_REMATCH[1]}")"
      continue
    fi

    if [[ "$line" =~ ^[[:space:]]*user_description:[[:space:]]*(.*)$ ]]; then
      users_desc[$user_idx]="$(yaml_scalar "${BASH_REMATCH[1]}")"
      continue
    fi

    if [[ "$line" =~ ^[[:space:]]*user_password:[[:space:]]*(.*)$ ]]; then
      users_pass[$user_idx]="$(yaml_scalar "${BASH_REMATCH[1]}")"
      continue
    fi

    if [[ "$line" =~ ^[[:space:]]*change_password_on_first_use:[[:space:]]*(.*)$ ]]; then
      users_chg[$user_idx]="$(yaml_scalar "${BASH_REMATCH[1]}")"
      users_chg[$user_idx]="${users_chg[$user_idx]^^}"

      # An explicitly empty value also defaults to Y.
      if [[ -z "${users_chg[$user_idx]}" ]]; then
        users_chg[$user_idx]="Y"
      fi

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

  echo 'ERROR: Unsupported or misplaced configuration line:' >&2
  echo "  $raw_line" >&2
  echo 'Use the structure shown in the example configuration.' >&2
  exit 1
done < "$CONFIG_FILE"

if [[ -n "$ws_name" ]]; then
  generate_sql
fi

cat <<'EOF_SQL' >> "$SQL_TMP"
exit;
EOF_SQL

mv -f -- "$SQL_TMP" "$SQL_FILE"
trap - EXIT

DEBUG= sql -S -L ${SQL_CLI_CONNECTION} @$SQL_FILE
if [ -z "${?:-1}" ]; then
  echo "ERROR: Database connection failed. Aborting."
  exit 1
fi

echo "INFO : APEX workspace creation completed successfully."
