begin;

do $$
begin
  if to_regprocedure('platform.execute_device_operation_before_participant_booking_type_edit(uuid,uuid,bytea,text,text,jsonb)') is null
     or to_regprocedure('reservations_private.mutate_scoped_before_participant_booking_type_edit(uuid,text,jsonb)') is null then
    raise exception 'RESERVATIONS_PARTICIPANT_BOOKING_TYPE_EDIT_MIGRATION_REQUIRED' using errcode='55000';
  end if;
end;
$$;

-- Restore the pre-feature canonical objects before replacing their definitions.
drop function platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb);
alter function platform.execute_device_operation_before_participant_booking_type_edit(uuid,uuid,bytea,text,text,jsonb)
  rename to execute_device_operation;

create or replace function platform.execute_device_operation(
  p_user_id uuid,p_session_id uuid,p_token_hash bytea,
  p_module text,p_operation text,p_args jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','platform','platform_private'
as $$
declare session platform_private.device_sessions%rowtype;
begin
  if p_module='reservations' and p_operation='update_participant_booking' then
    if coalesce(auth.jwt()->>'role','')<>'service_role' then
      raise exception 'PLATFORM_OPERATION_BACKEND_REQUIRED' using errcode='42501';
    end if;
    if p_args is null or jsonb_typeof(p_args)<>'object'
       or p_args ?| array['organization_id','p_organization_id','scope_partition_id','p_scope_partition_id','device_id','p_device_id','actor_user_id','p_actor_user_id','actor_device_id','p_actor_device_id','p_conference_person_id','conference_person_id'] then
      raise exception 'PLATFORM_OPERATION_ARGUMENT_INVALID' using errcode='22023';
    end if;
    perform platform_private.require_exact_jsonb_keys(p_args,array[
      'p_operation_id','p_booking_id','p_expected_revision','p_booking_type_id',
      'p_full_name','p_phone','p_age','p_church','p_governorate',
      'p_city_or_village','p_service_sector','p_service_sector_other','p_notes'
    ]);

    select item.* into session
    from platform_private.device_sessions item
    join platform.device_key_bindings binding on binding.id=item.binding_id
    join platform.user_device_authorizations device_authorization on device_authorization.id=item.device_authorization_id
    join platform.devices device on device.id=item.device_id
    join platform.profiles profile on profile.user_id=item.user_id
    where item.id=p_session_id and item.user_id=p_user_id and item.token_hash=p_token_hash
      and item.purpose='PLATFORM_DEVICE_SESSION' and item.revoked_at is null
      and item.expires_at>statement_timestamp()
      and binding.user_id=item.user_id and binding.device_id=item.device_id
      and binding.device_authorization_id=item.device_authorization_id
      and binding.public_key_thumbprint=item.public_key_thumbprint
      and binding.algorithm='ECDSA_P256_SHA256' and binding.lifecycle_status='active'
      and binding.revoked_at is null and binding.retired_at is null
      and device_authorization.user_id=item.user_id and device_authorization.device_id=item.device_id
      and device_authorization.status='approved' and device_authorization.revoked_at is null
      and device.lifecycle_status='active' and device.retired_at is null
      and device.compromised_at is null and profile.account_status='approved';
    if not found then
      raise exception 'DEVICE_SESSION_INVALID' using errcode='42501';
    end if;

    perform set_config('request.jwt.claims',jsonb_build_object('sub',p_user_id,'role','service_role')::text,true);
    perform set_config('platform.phase1c_context',jsonb_build_object(
      'purpose','PLATFORM_DEVICE_SESSION_DISPATCH','session_id',session.id,
      'user_id',session.user_id,'device_id',session.device_id,
      'authorization_id',session.device_authorization_id,'binding_id',session.binding_id,
      'token_hash',encode(p_token_hash,'hex')
    )::text,true);
    return reservations_private.mutate_scoped(session.device_id,p_operation,p_args);
  end if;

  if p_module<>'conference' or p_operation<>'list_module_permission_resources_for_administration' then
    return platform.execute_device_operation_pre_generic_permission_resource_administration(
      p_user_id,p_session_id,p_token_hash,p_module,p_operation,p_args
    );
  end if;
  if coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'PLATFORM_OPERATION_BACKEND_REQUIRED' using errcode='42501';
  end if;
  if p_args is null or jsonb_typeof(p_args)<>'object'
     or p_args ?| array['organization_id','p_organization_id','scope_partition_id','p_scope_partition_id','device_id','p_device_id','actor_user_id','p_actor_user_id','actor_device_id','p_actor_device_id'] then
    raise exception 'PLATFORM_OPERATION_ARGUMENT_INVALID' using errcode='22023';
  end if;

  select item.* into session
  from platform_private.device_sessions item
  join platform.device_key_bindings binding on binding.id=item.binding_id
  join platform.user_device_authorizations device_authorization on device_authorization.id=item.device_authorization_id
  join platform.devices device on device.id=item.device_id
  join platform.profiles profile on profile.user_id=item.user_id
  where item.id=p_session_id and item.user_id=p_user_id and item.token_hash=p_token_hash
    and item.purpose='PLATFORM_DEVICE_SESSION' and item.revoked_at is null
    and item.expires_at>statement_timestamp()
    and binding.user_id=item.user_id and binding.device_id=item.device_id
    and binding.device_authorization_id=item.device_authorization_id
    and binding.public_key_thumbprint=item.public_key_thumbprint
    and binding.algorithm='ECDSA_P256_SHA256' and binding.lifecycle_status='active'
    and binding.revoked_at is null and binding.retired_at is null
    and device_authorization.user_id=item.user_id and device_authorization.device_id=item.device_id
    and device_authorization.status='approved' and device_authorization.revoked_at is null
    and device.lifecycle_status='active' and device.retired_at is null
    and device.compromised_at is null and profile.account_status='approved';
  if not found then
    raise exception 'DEVICE_SESSION_INVALID' using errcode='42501';
  end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',p_user_id,'role','service_role')::text,true);
  perform set_config('platform.phase1c_context',jsonb_build_object(
    'purpose','PLATFORM_DEVICE_SESSION_DISPATCH','session_id',session.id,
    'user_id',session.user_id,'device_id',session.device_id,
    'authorization_id',session.device_authorization_id,'binding_id',session.binding_id,
    'token_hash',encode(p_token_hash,'hex')
  )::text,true);
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_module_key','p_resource_type']);
  return public.list_module_permission_resources_for_administration(
    session.device_id,p_args->>'p_module_key',p_args->>'p_resource_type'
  );
end;
$$;

revoke all on function platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)
  from public,anon,authenticated,service_role;
grant execute on function platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)
  to service_role;

drop function reservations_private.mutate_scoped(uuid,text,jsonb);
alter function reservations_private.mutate_scoped_before_participant_booking_type_edit(uuid,text,jsonb)
  rename to mutate_scoped;

-- Patch the one canonical operation branch while retaining every other operation
-- byte-for-byte from the established scoped mutation definition.
do $$
declare
  v_definition text;
  v_old text:=$old$
 if p_operation='update_participant_booking' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_expected_revision','p_full_name','p_phone','p_age','p_church','p_governorate','p_city_or_village','p_service_sector','p_service_sector_other','p_notes']); v_context:=reservations_private.resolve_booking_scope(p_device_id,(p_args->>'p_booking_id')::uuid,'reservations.booking.update'); v_actor:=(v_context->>'actorUserId')::uuid;
  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_booking from reservations.bookings where id=(v_context->>'bookingId')::uuid and event_id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for update; if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002'; end if; if v_booking.revision<>(p_args->>'p_expected_revision')::bigint then raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001'; end if;
  update reservations.participants set full_name=btrim(p_args->>'p_full_name'),phone=btrim(p_args->>'p_phone'),age=(p_args->>'p_age')::integer,church=coalesce(p_args->>'p_church',''),governorate=btrim(p_args->>'p_governorate'),city_or_village=coalesce(p_args->>'p_city_or_village',''),service_sector=p_args->>'p_service_sector',service_sector_other=nullif(btrim(p_args->>'p_service_sector_other'),''),notes=nullif(p_args->>'p_notes',''),revision=revision+1,updated_at=statement_timestamp(),updated_by=v_actor where id=v_booking.participant_id and scope_partition_id=v_booking.scope_partition_id and organization_id is not distinct from v_booking.organization_id; if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002'; end if; update reservations.bookings set notes=nullif(p_args->>'p_notes',''),revision=revision+1,updated_at=statement_timestamp(),updated_by=v_actor where id=v_booking.id and event_id=v_booking.event_id and scope_partition_id=v_booking.scope_partition_id and organization_id is not distinct from v_booking.organization_id returning revision into v_revision; v_result:=jsonb_build_object('bookingId',v_booking.id,'revision',v_revision); perform reservations_private.audit(v_context,'booking.updated','booking',v_booking.id,v_operation_id,to_jsonb(v_booking),v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;$old$;
  v_new text:=$new$
 if p_operation='update_participant_booking' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_expected_revision','p_booking_type_id','p_full_name','p_phone','p_age','p_church','p_governorate','p_city_or_village','p_service_sector','p_service_sector_other','p_notes']); v_context:=reservations_private.resolve_booking_scope(p_device_id,(p_args->>'p_booking_id')::uuid,'reservations.booking.update'); v_actor:=(v_context->>'actorUserId')::uuid;
  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_booking from reservations.bookings where id=(v_context->>'bookingId')::uuid and event_id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid and organization_id is not distinct from nullif(v_context->>'organizationId','')::uuid for update; if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002'; end if; if v_booking.revision<>(p_args->>'p_expected_revision')::bigint then raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001'; end if;
  select * into v_type from reservations.booking_types where id=(p_args->>'p_booking_type_id')::uuid and event_id=v_booking.event_id and scope_partition_id=v_booking.scope_partition_id and organization_id is not distinct from v_booking.organization_id for key share; if not found then raise exception 'RESERVATIONS_BOOKING_TYPE_EVENT_MISMATCH' using errcode='22023'; end if; if v_type.id<>v_booking.booking_type_id and not v_type.active then raise exception 'RESERVATIONS_BOOKING_TYPE_INACTIVE' using errcode='22023'; end if;
  update reservations.participants set full_name=btrim(p_args->>'p_full_name'),phone=btrim(p_args->>'p_phone'),age=(p_args->>'p_age')::integer,church=coalesce(p_args->>'p_church',''),governorate=btrim(p_args->>'p_governorate'),city_or_village=coalesce(p_args->>'p_city_or_village',''),service_sector=p_args->>'p_service_sector',service_sector_other=nullif(btrim(p_args->>'p_service_sector_other'),''),notes=nullif(p_args->>'p_notes',''),revision=revision+1,updated_at=statement_timestamp(),updated_by=v_actor where id=v_booking.participant_id and scope_partition_id=v_booking.scope_partition_id and organization_id is not distinct from v_booking.organization_id; if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002'; end if; update reservations.bookings set booking_type_id=v_type.id,booking_type_name_snapshot=v_type.name,price_snapshot=v_type.price,notes=nullif(p_args->>'p_notes',''),revision=revision+1,updated_at=statement_timestamp(),updated_by=v_actor where id=v_booking.id and event_id=v_booking.event_id and scope_partition_id=v_booking.scope_partition_id and organization_id is not distinct from v_booking.organization_id returning revision into v_revision; v_result:=jsonb_build_object('bookingId',v_booking.id,'bookingTypeId',v_type.id,'revision',v_revision); perform reservations_private.audit(v_context,'booking.updated','booking',v_booking.id,v_operation_id,to_jsonb(v_booking),v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;$new$;
begin
  select pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure)
    into v_definition;
  if length(v_definition)-length(replace(v_definition,v_old,''))<>length(v_old) then
    raise exception 'RESERVATIONS_CANONICAL_MUTATION_DEFINITION_UNEXPECTED' using errcode='55000';
  end if;
  execute replace(v_definition,v_old,v_new);
end;
$$;

revoke all on function reservations_private.mutate_scoped(uuid,text,jsonb)
  from public,anon,authenticated,service_role;
grant execute on function reservations_private.mutate_scoped(uuid,text,jsonb)
  to postgres;

do $$
begin
  if to_regprocedure('platform.execute_device_operation_before_participant_booking_type_edit(uuid,uuid,bytea,text,text,jsonb)') is not null
     or to_regprocedure('reservations_private.mutate_scoped_before_participant_booking_type_edit(uuid,text,jsonb)') is not null then
    raise exception 'RESERVATIONS_PARTICIPANT_BOOKING_TYPE_EDIT_WRAPPER_REMAINS' using errcode='55000';
  end if;
end;
$$;

commit;
