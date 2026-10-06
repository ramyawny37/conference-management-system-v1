begin;

do $$
declare
  v_definition text;
  v_marker text := E'begin\n  if p_module=''conference'' then';
  v_replacement text := E'begin\n  if p_module=''platform'' then\n    if p_operation=''list_module_permission_resources_for_administration'' then\n      -- Keep this newer administration operation on its current hardened dispatcher until flattening.\n      return platform.execute_device_operation_pre_generic_permission_resource_administration(\n        p_user_id,p_session_id,p_token_hash,''conference'',p_operation,p_args\n      );\n    end if;\n    return platform.execute_conference_device_operation_phase1c_core(\n      p_user_id,p_session_id,p_token_hash,p_operation,p_args\n    );\n  end if;\n\n  if p_module=''conference'' then';
begin
  select pg_get_functiondef(p.oid) into v_definition
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='platform' and p.proname='execute_device_operation'
    and pg_get_function_identity_arguments(p.oid)=
      'p_user_id uuid, p_session_id uuid, p_token_hash bytea, p_module text, p_operation text, p_args jsonb';
  if v_definition is null or position(v_marker in v_definition)=0 then
    raise exception 'PLATFORM_MODULE_CUTOVER_PREDECESSOR_MISMATCH' using errcode='55000';
  end if;
  execute replace(v_definition,v_marker,v_replacement);
end $$;

commit;
