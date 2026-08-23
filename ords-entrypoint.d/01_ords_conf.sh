#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# ORDS Runtime Configuration
#
# Applies project-specific ORDS settings before the ORDS server starts.
# ==============================================================================

# Limit the ORDS JDBC connection pool to 15 connections for this environment.
ords config set jdbc.MaxLimit "15"
