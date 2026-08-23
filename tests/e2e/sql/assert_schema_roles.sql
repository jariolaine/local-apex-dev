whenever oserror exit failure -- noqa: PRS
whenever sqlerror exit sql.sqlcode -- noqa: PRS

set feedback off
set verify off

define pdb_name = '&1'
define schema_name = '&2'
define role_one = '&3'
define role_two = '&4'

alter session set container = &&pdb_name;

set serveroutput on size unlimited
set feedback off
set verify off

declare
  l_count number;
begin
  select count(*)
    into l_count
    from dba_users
   where username = upper('&&schema_name');

  if l_count <> 1 then
    raise_application_error(-20001, 'FAIL : Schema &&schema_name does not exist.');
  end if;

  select count(distinct granted_role)
    into l_count
    from dba_role_privs
   where grantee = upper('&&schema_name')
     and granted_role in (upper('&&role_one'), upper('&&role_two'));

  if l_count <> 2 then
    raise_application_error(
      -20002,
      'FAIL : Schema &&schema_name does not have both expected roles.'
    );
  end if;

  dbms_output.put_line(
    'PASS : Schema &&schema_name exists and has &&role_one and &&role_two.'
  );
end;
/

exit success
