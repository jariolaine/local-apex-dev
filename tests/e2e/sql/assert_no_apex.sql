whenever oserror exit failure -- noqa: PRS
whenever sqlerror exit sql.sqlcode -- noqa: PRS

set feedback off
set verify off

define pdb_name = '&1'
define schema_name = '&2'

alter session set container = &&pdb_name;

-- Keep these after ALTER SESSION. SQLcl output settings can be affected
-- by the session change in this execution environment.
set serveroutput on size unlimited
set feedback off
set verify off

declare
  l_count number;
begin
  select count(*)
    into l_count
    from dba_registry
   where comp_id = 'APEX';

  if l_count <> 0 then
    raise_application_error(
      -20001,
      'FAIL : APEX is present in &&pdb_name.'
    );
  end if;

  select count(*)
    into l_count
    from dba_users
   where username = upper('&&schema_name');

  if l_count <> 0 then
    raise_application_error(
      -20002,
      'FAIL : APEX workspace schema &&schema_name unexpectedly exists.'
    );
  end if;

  dbms_output.put_line(
    'PASS : APEX is not installed and workspace schema &&schema_name does not exist.'
  );
end;
/

exit success