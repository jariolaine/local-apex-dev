#!/usr/bin/env bash
# ==============================================================================
# Common Bash Functions
#
# Provides utility functions for common bash operations and variables.
# ==============================================================================
# Construct the SQLcl connection string.
# Uses CONN_STRING if provided; otherwise, falls back to DBHOST:DBPORT/DBSERVICENAME.
SQL_CLI_CONNECTION="sys/\"${ORACLE_PWD}\"@${CONN_STRING:-${DBHOST}:${DBPORT}/${DBSERVICENAME}} as sysdba"

error() {
  echo "ERROR : $*" >&2
  return 1
}

info() {
  echo "INFO : $*"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

is_apex_installed() {
  # Query DBA_REGISTRY to ensure the APEX component is valid and installed
  local installed
  installed=$(DEBUG="" sql -S -L "${SQL_CLI_CONNECTION}" <<'EOF_SQL'
  set verify off
  set heading off
  set feedback off
  set trim on
  set pages 0
  select comp_id
  from dba_registry
  where comp_id = 'APEX'
    and status = 'VALID';
  exit
EOF_SQL
  )
  installed="$(trim "$installed")"
  [[ "$installed" == "APEX" ]] || return 1
  return 0
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
    printf "ERROR : Invalid %s '%s'.\n" "$label" "$value" >&2
    echo 'Use letters, numbers, _, $ or #, starting with a letter.' >&2
    exit 1
  fi
}

validate_schema_password() {
  local password="$1"
  if [[ "$password" == *'"'* ]]; then
    error 'Schema password cannot contain a double quote (").'
    exit 1
  fi
  if [[ "$password" == *$'\n'* || "$password" == *$'\r'* ]]; then
    error 'Schema password cannot contain line breaks.'
    exit 1
  fi
}

run_sql() {
  local sql_file
  sql_file="${1}"
  if ! DEBUG="" sql -S -L "${SQL_CLI_CONNECTION}" "@${sql_file}"; then
    return 1
  fi
  return 0
}