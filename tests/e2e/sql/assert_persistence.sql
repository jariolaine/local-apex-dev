whenever oserror exit failure -- noqa: PRS
whenever sqlerror exit sql.sqlcode -- noqa: PRS

set serveroutput on size unlimited
set feedback off
set verify off

declare
  l_value varchar2(100);
begin
  execute immediate
    'select test_value from e2e_persistence_test where id = 1'
    into l_value;

  if l_value <> 'PERSISTED' then
    raise_application_error(-20001, 'FAIL : Persistence sentinel has the wrong value.');
  end if;

  dbms_output.put_line(
    'PASS : Persistence sentinel exists with the expected value.'
  );
end;
/

exit success
