-- Canonicalize Conference device-operation identity semantics.
-- Actor device identity is always derived from the verified Platform device session.
-- p_actor_device_id is therefore forbidden. p_device_id is an operation target and
-- is accepted only when the Conference operation's exact-key contract requires it.
-- Warehouse semantics remain enforced by platform.execute_device_operation and are
-- intentionally untouched by this migration.

do $$
declare
  v_signature regprocedure := 'platform.execute_conference_device_operation_phase1c_core(uuid,uuid,bytea,text,jsonb)'::regprocedure;
  v_definition text;
  v_legacy_guard text := 'if p_args ? ''p_actor_device_id'' or (p_args ? ''p_device_id'' and p_operation<>''approve_pending_device_authorization'') then raise exception ''ACTOR_DEVICE_OVERRIDE_DENIED'' using errcode=''22023''; end if;';
  v_canonical_guard text := 'if p_args ? ''p_actor_device_id'' then raise exception ''ACTOR_DEVICE_OVERRIDE_DENIED'' using errcode=''22023''; end if;';
  v_occurrences integer;
begin
  v_definition := pg_get_functiondef(v_signature);

  -- Fail closed if the deployed definition is not the exact reviewed predecessor.
  v_occurrences := (length(v_definition) - length(replace(v_definition, v_legacy_guard, ''))) / length(v_legacy_guard);
  if v_occurrences <> 1 then
    raise exception 'CONFERENCE_DEVICE_GUARD_PRECONDITION_FAILED' using errcode='55000';
  end if;

  v_definition := replace(v_definition, v_legacy_guard, v_canonical_guard);
  execute v_definition;

  -- Verify the replacement itself and the operation-level exact-key boundary.
  v_definition := pg_get_functiondef(v_signature);
  if position(v_legacy_guard in v_definition) <> 0
     or position(v_canonical_guard in v_definition) = 0
     or position('when ''approve_member_device'',''reject_member_pending_device'',''revoke_member_device'' then' in v_definition) = 0
     or position('require_exact_jsonb_keys(p_args,array[''p_organization_id'',''p_target_user_id'',''p_device_id'',''p_operation_id''])' in v_definition) = 0 then
    raise exception 'CONFERENCE_DEVICE_GUARD_POSTCONDITION_FAILED' using errcode='55000';
  end if;
end $$;

comment on function platform.execute_conference_device_operation_phase1c_core(uuid,uuid,bytea,text,jsonb) is
'Canonical Conference device dispatcher: actor device is derived exclusively from the verified Platform session; p_actor_device_id is forbidden; p_device_id is target identity only where each operation exact-key contract explicitly requires it.';
