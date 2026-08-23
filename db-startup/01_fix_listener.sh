#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# Oracle Net Hostname Configuration
#
# Ensures the persisted listener and TNS configuration accept connections
# through the container network instead of using an old container hostname.
# ==============================================================================

# ------------------------------------------------------------------------------
# Configuration Variables
# ------------------------------------------------------------------------------
LISTENER_ORA="/opt/oracle/oradata/dbconfig/FREE/listener.ora"
TNSNAMES_ORA="/opt/oracle/oradata/dbconfig/FREE/tnsnames.ora"

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
if [ -f "${LISTENER_ORA}" ]; then
  echo "INFO : Ensuring listener HOST uses 0.0.0.0 in ${LISTENER_ORA}."
  sed -i "s/(HOST = [^)]*)/\(HOST = 0.0.0.0\)/" "${LISTENER_ORA}"
else
  echo "WARNING : Listener configuration file not found: ${LISTENER_ORA}" >&2
fi

if [ -f "${TNSNAMES_ORA}" ]; then
  echo "INFO : Ensuring TNS HOST uses 0.0.0.0 in ${TNSNAMES_ORA}."
  sed -i "s/(HOST = [^)]*)/\(HOST = 0.0.0.0\)/" "${TNSNAMES_ORA}"
else
  echo "WARNING : TNS configuration file not found: ${TNSNAMES_ORA}" >&2
fi