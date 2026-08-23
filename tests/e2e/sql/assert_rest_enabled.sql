whenever oserror exit failure -- noqa: PRS
whenever sqlerror exit sql.sqlcode -- noqa: PRS

set feedback off
set verify off

define pdb_name = '&1'
define schema_name = '&2'

alter session set container = &&pdb_name;

set serveroutput on size unlimited
set feedback off
set verify off

declare
  l_count number;
begin
  select count(*)
    into l_count
    from dba_ords_schemas
   where parsing_schema = upper('&&schema_name');

  if l_count <> 1 then
    raise_application_error(-20001, 'FAIL : Schema &&schema_name not found from DBA_ORDS_SCHEMAS.');
  end if;

  dbms_output.put_line(
    'PASS : Schema &&schema_name is REST enabled.'
  );
end;
/

exit success
