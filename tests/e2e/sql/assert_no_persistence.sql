whenever oserror exit failure -- noqa: PRS
whenever sqlerror exit sql.sqlcode -- noqa: PRS

set serveroutput on size unlimited
set feedback off
set verify off

declare
  l_count number;
begin
  select count(*) into l_count
    from user_tables
   where table_name = 'E2E_PERSISTENCE_TEST';

  if l_count <> 0 then
    raise_application_error(
      -20001,
      'FAIL : Persistence sentinel unexpectedly exists.'
    );
  end if;

  dbms_output.put_line(
    'PASS : Persistence sentinel does not exist.'
  )
  ;
end;
/

exit success
