whenever oserror exit failure -- noqa: PRS
whenever sqlerror exit sql.sqlcode -- noqa: PRS

set serveroutput on size unlimited
set feedback off
set verify off

define model_name = '&1'

declare
  l_response dbms_cloud_types.resp;
  l_status   pls_integer;
  l_body     clob;
begin
  -- Test APEX_WEB_SERVICE can reach Ollama through HTTPS gateway.
  l_body := apex_web_service.make_rest_request(
    p_url         => 'https://ollama-api-gateway/api/tags'
  , p_http_method => 'GET'
  );
  -- Check the HTTP status code returned by the Ollama HTTPS gateway.
  l_status := apex_web_service.g_status_code;
  if l_status <> 200 then
    raise_application_error(
      -20001,
      'FAIL : Ollama HTTPS gateway returned HTTP ' || l_status || '.'
    );
  end if;
  -- Verify the response body to check if it contains the expected model name.
  if dbms_lob.instr(l_body, '&&model_name') = 0 then
    raise_application_error(
      -20002,
      'FAIL : Ollama HTTPS gateway response does not contain model &&model_name.'
    );
  end if;

  -- Test DBMS_CLOUD can reach Ollama through HTTPS gateway.
  l_response := dbms_cloud.send_request(
    credential_name => null
  , uri             => 'https://ollama-api-gateway/api/tags'
  , method          => dbms_cloud.method_get
  );

  l_status := dbms_cloud.get_response_status_code(l_response);
  l_body   := dbms_cloud.get_response_text(l_response);
  -- Check the HTTP status code returned by the Ollama HTTPS gateway.
  if l_status <> 200 then
    raise_application_error(
      -20001,
      'FAIL : Ollama HTTPS gateway returned HTTP ' || l_status || '.'
    );
  end if;
  --  Verify the response body to check if it contains the expected model name.
  if dbms_lob.instr(l_body, '&&model_name') = 0 then
    raise_application_error(
      -20002,
      'FAIL : Ollama HTTPS gateway response does not contain model &&model_name.'
    );
  end if;
  -- Output a success message if both tests pass.
  dbms_output.put_line(
    'PASS : APEX_WEB_SERVICE and DBMS_CLOUD reached Ollama through HTTPS gateway and found &&model_name.'
  );
end;
/

exit success
