whenever oserror exit failure -- noqa: PRS
whenever sqlerror exit sql.sqlcode -- noqa: PRS

set serveroutput on
set feedback off
set verify off

declare
  l_count number;
begin
  select count(*)
    into l_count
    from user_tables
   where table_name = 'E2E_PERSISTENCE_TEST';

  if l_count = 1 then
    execute immediate 'drop table e2e_persistence_test purge';
  end if;

  execute immediate q'[
    create table e2e_persistence_test (
      id number primary key,
      test_value varchar2(100) not null
    )
  ]';

  execute immediate q'[
    insert into E2E_PERSISTENCE_TEST (id, test_value)
    values (1, 'PERSISTED')
  ]';

  commit;
  dbms_output.put_line('PASS : Persistence sentinel created.');
end;
/

exit success
