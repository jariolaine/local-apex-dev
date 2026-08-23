whenever oserror exit failure -- noqa: PRS
whenever sqlerror exit sql.sqlcode -- noqa: PRS

set serveroutput on size unlimited
set feedback off
set verify off

define pdb_name = '&1'

declare
  l_missing number;
begin
  with expected_packages (object_name) as (
    select 'DBMS_CLOUD'               from dual union all
    select 'DBMS_CLOUD_PIPELINE'      from dual union all
    select 'DBMS_CLOUD_REPO'          from dual union all
    select 'DBMS_CLOUD_NOTIFICATION'  from dual union all
    select 'DBMS_CLOUD_AI'            from dual union all
    select 'DBMS_CLOUD_AI_AGENT'      from dual
  ),
  expected_types (object_type) as (
    select 'PACKAGE'      from dual union all
    select 'PACKAGE BODY' from dual
  ),
  expected_containers (con_id) as (
    select con_id
      from v$containers
     where name in ('CDB$ROOT', upper('&&pdb_name'))
  ),
  missing_objects as (
    select c.con_id, p.object_name, t.object_type
      from expected_containers c
      cross join expected_packages p
      cross join expected_types t
    minus
    select o.con_id, o.object_name, o.object_type
      from cdb_objects o
     where o.owner = 'C##CLOUD$SERVICE'
       and o.status = 'VALID'
  )
  select count(*)
    into l_missing
    from missing_objects;

  if l_missing <> 0 then
    raise_application_error(
      -20001,
      'FAIL : DBMS_CLOUD validation failed. Missing or invalid expected objects: ' || l_missing
    );
  end if;

  dbms_output.put_line(
    'PASS : Required DBMS_CLOUD packages are VALID in CDB$ROOT and &&pdb_name.'
  );
end;
/

exit success
