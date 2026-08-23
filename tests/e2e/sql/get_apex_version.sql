whenever oserror exit failure -- noqa: PRS
whenever sqlerror exit sql.sqlcode -- noqa: PRS

set heading off
set feedback off
set verify off
set echo off
set trim on
set pages 0

define pdb_name = '&1'

alter session set container = &&pdb_name;

select version
  from dba_registry
 where comp_id = 'APEX'
  and status = 'VALID';

exit success