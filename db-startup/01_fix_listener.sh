#!/bin/bash

## Variables
LISTENER_ORA="/opt/oracle/oradata/dbconfig/FREE/listener.ora"
TNSNAMES_ORA="/opt/oracle/oradata/dbconfig/FREE/tnsnames.ora"

## Code
if [ -f "${LISTENER_ORA}" ]; then
  echo ""
  echo "****************************************************************"
  echo "** Fixing Oracle TNS listener hostname configuration"
  echo "** File ${LISTENER_ORA}"
  echo "****************************************************************"

  sed -i "s/(HOST = [^)]*)/\(HOST = 0.0.0.0\)/" "${LISTENER_ORA}"
fi

if [ -f "${TNSNAMES_ORA}" ]; then
  echo ""
  echo "****************************************************************"
  echo "** Fixing Oracle TNS names hostname configuration"
  echo "** File ${TNSNAMES_ORA}"
  echo "****************************************************************"

  sed -i "s/(HOST = [^)]*)/\(HOST = 0.0.0.0\)/" "${TNSNAMES_ORA}"
fi
