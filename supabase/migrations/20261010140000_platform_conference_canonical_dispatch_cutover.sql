begin;

-- The public Platform Edge Function is already the single browser transport.
-- Cut Conference out of the historical pre_* chain at the database entry point
-- and route it through the canonical Conference dispatcher.
do $$
declare
  v_definition text;
  v_marker text := E'begin\n  if p_module=\'reservations\'';
  v_replacement text := E'begin\n  if p_module=\'conference\' then\n    return platform.execute_conference_device_operation(\n      p_user_id,p_session_id,p_token_hash,p_operation,p_args\n    );\n  end if;\n\n  if p_module=\'reservations\'';
begin
  select pg_get_functiondef(p.oid)
  into v_definition
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where p.prokind='f'
    and n.nspname='platform'
    and p.proname='execute_device_operation'
    and pg_get_function_identity_arguments(p.oid)=
      'p_user_id uuid, p_session_id uuid, p_token_hash bytea, p_module text, p_operation text, p_args jsonb';

  if v_definition is null or position(v_marker in v_definition)=0 then
    raise exception 'PLATFORM_DEVICE_OPERATION_CUTOVER_PREDECESSOR_MISMATCH'
      using errcode='55000';
  end if;

  execute replace(v_definition,v_marker,v_replacement);
end $$;

commit;
