#!/bin/bash

# ==============================================================================
# Oracle ORDS Configuration
#
# Automates ORDS configuration.
# ==============================================================================

# ORDS_CONFIG="/etc/ords/config"
ords config set jdbc.MaxLimit "15"
