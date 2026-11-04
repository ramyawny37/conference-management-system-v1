begin;

do $$
declare
  v_definition text;
  v_marker text := E'  end if;\n  return platform.execute_conference_device_operation_phase1c_core(\n    p_user_id,p_session_id,p_token_hash,p_operation,p_args\n  );';
  v_replacement text := E'  elsif p_operation in (''acquire_conference_lock'',''renew_conference_lock'') then\n    perform platform_private.require_exact_jsonb_keys(p_args,array[''p_conference_id'',''p_lock_token'',''p_ttl_seconds'']);\n    if p_operation=''acquire_conference_lock'' then\n      return public.device_guarded_acquire_conference_lock(p_actor_device_id,(p_args->>''p_conference_id'')::uuid,(p_args->>''p_lock_token'')::uuid,(p_args->>''p_ttl_seconds'')::integer);\n    end if;\n    return public.device_guarded_renew_conference_lock(p_actor_device_id,(p_args->>''p_conference_id'')::uuid,(p_args->>''p_lock_token'')::uuid,(p_args->>''p_ttl_seconds'')::integer);\n  elsif p_operation=''release_conference_lock'' then\n    perform platform_private.require_exact_jsonb_keys(p_args,array[''p_conference_id'',''p_lock_token'']);\n    return public.device_guarded_release_conference_lock(p_actor_device_id,(p_args->>''p_conference_id'')::uuid,(p_args->>''p_lock_token'')::uuid);\n  elsif p_operation=''get_conference_lock'' then\n    perform platform_private.require_exact_jsonb_keys(p_args,array[''p_conference_id'']);\n    return public.device_guarded_get_conference_lock(p_actor_device_id,(p_args->>''p_conference_id'')::uuid);\n  elsif p_operation in (''acquire_conference_section_lock'',''renew_conference_section_lock'') then\n    perform platform_private.require_exact_jsonb_keys(p_args,array[''p_conference_id'',''p_section'',''p_lock_token'',''p_ttl_seconds'']);\n    if p_operation=''acquire_conference_section_lock'' then\n      return public.acquire_conference_section_lock((p_args->>''p_conference_id'')::uuid,p_args->>''p_section'',p_actor_device_id,(p_args->>''p_lock_token'')::uuid,(p_args->>''p_ttl_seconds'')::integer);\n    end if;\n    return public.renew_conference_section_lock((p_args->>''p_conference_id'')::uuid,p_args->>''p_section'',p_actor_device_id,(p_args->>''p_lock_token'')::uuid,(p_args->>''p_ttl_seconds'')::integer);\n  elsif p_operation=''release_conference_section_lock'' then\n    perform platform_private.require_exact_jsonb_keys(p_args,array[''p_conference_id'',''p_section'',''p_lock_token'']);\n    return public.release_conference_section_lock((p_args->>''p_conference_id'')::uuid,p_args->>''p_section'',p_actor_device_id,(p_args->>''p_lock_token'')::uuid);\n  elsif p_operation=''get_conference_section_lock'' then\n    perform platform_private.require_exact_jsonb_keys(p_args,array[''p_conference_id'',''p_section'']);\n    return public.get_conference_section_lock((p_args->>''p_conference_id'')::uuid,p_args->>''p_section'',p_actor_device_id);\n  end if;\n  return platform.execute_conference_device_operation_phase1c_core(\n    p_user_id,p_session_id,p_token_hash,p_operation,p_args\n  );';
begin
  select pg_get_functiondef(p.oid) into v_definition
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where p.prokind='f' and n.nspname='platform_private'
    and p.proname='route_canonical_conference_operation';

  if v_definition is null or position(v_marker in v_definition)=0 then
    raise exception 'CANONICAL_CONFERENCE_LOCK_CUTOVER_PREDECESSOR_MISMATCH' using errcode='55000';
  end if;
  execute replace(v_definition,v_marker,v_replacement);
end $$;

commit;
