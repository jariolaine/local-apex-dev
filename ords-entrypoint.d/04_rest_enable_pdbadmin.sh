#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# PDBADMIN Database Actions Access
#
# REST-enable PDBADMIN so Oracle Database Actions remains available even when
# the environment is started without APEX.
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper functions from the common.sh file
# shellcheck source=ords-entrypoint.d/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SQL_FILE="${HOME%/}/rest_enable_pdbadmin.sql"
SQL_TMP="${SQL_FILE}.tmp"


echo "----------------------------------------"
info "Generating SQL file for REST enable PDBADMIN..."

cat <<'EOF_SQL' > "${SQL_TMP}"
whenever oserror exit failure
whenever sqlerror exit sql.sqlcode

set serveroutput on
set heading off
set feedback off
set pagesize 0
set verify off
set trim on

begin
  ords_admin.enable_schema(
    p_schema          => 'PDBADMIN'
  , p_auto_rest_auth  => true
  );
end;
/
EOF_SQL

echo "----------------------------------------"
info "Executing SQL..."

mv -f -- "${SQL_TMP}" "${SQL_FILE}"

if ! run_sql "${SQL_FILE}"; then
  error "Execution of SQL file failed. Review the SQLcl output above."
  exit 1
fi
info "REST enabled PDBADMIN successfully."