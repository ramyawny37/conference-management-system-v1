-- Extend the existing protected participant/booking mutation without changing
-- its device-session, permission, idempotency, or optimistic-lock boundary.
alter function platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)
  rename to execute_device_operation_before_participant_booking_type_edit;

create function platform.execute_device_operation(
  p_user_id uuid,
  p_session_id uuid,
  p_token_hash bytea,
  p_module text,
  p_operation text,
  p_args jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','platform','platform_private','reservations','reservations_private'
as $$
declare
  v_session platform_private.device_sessions%rowtype;
begin
  if p_module<>'reservations' or p_operation<>'update_participant_booking' then
    return platform.execute_device_operation_before_participant_booking_type_edit(
      p_user_id,p_session_id,p_token_hash,p_module,p_operation,p_args
    );
  end if;
  if coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'PLATFORM_OPERATION_BACKEND_REQUIRED' using errcode='42501';
  end if;
  if p_args is null or jsonb_typeof(p_args)<>'object'
     or p_args ?| array[
       'organization_id','p_organization_id','scope_partition_id',
       'p_scope_partition_id','device_id','p_device_id','actor_user_id',
       'p_actor_user_id','actor_device_id','p_actor_device_id',
       'p_conference_person_id','conference_person_id'
     ] then
    raise exception 'PLATFORM_OPERATION_ARGUMENT_INVALID' using errcode='22023';
  end if;
  perform platform_private.require_exact_jsonb_keys(p_args,array[
    'p_operation_id','p_booking_id','p_expected_revision','p_booking_type_id',
    'p_full_name','p_phone','p_age','p_church','p_governorate',
    'p_city_or_village','p_service_sector','p_service_sector_other','p_notes'
  ]);

  select s.* into v_session
  from platform_private.device_sessions s
  join platform.device_key_bindings b on b.id=s.binding_id
  join platform.user_device_authorizations a on a.id=s.device_authorization_id
  join platform.devices d on d.id=s.device_id
  join platform.profiles p on p.user_id=s.user_id
  where s.id=p_session_id and s.user_id=p_user_id
    and s.token_hash=p_token_hash
    and s.purpose='PLATFORM_DEVICE_SESSION'
    and s.revoked_at is null and s.expires_at>statement_timestamp()
    and b.user_id=s.user_id and b.device_id=s.device_id
    and b.device_authorization_id=s.device_authorization_id
    and b.public_key_thumbprint=s.public_key_thumbprint
    and b.algorithm='ECDSA_P256_SHA256'
    and b.lifecycle_status='active' and b.revoked_at is null
    and b.retired_at is null
    and a.user_id=s.user_id and a.device_id=s.device_id
    and a.status='approved' and a.revoked_at is null
    and d.lifecycle_status='active' and d.retired_at is null
    and d.compromised_at is null and p.account_status='approved';
  if not found then
    raise exception 'DEVICE_SESSION_INVALID' using errcode='42501';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',p_user_id,'role','service_role')::text,true
  );
  perform set_config(
    'platform.phase1c_context',
    jsonb_build_object(
      'purpose','PLATFORM_DEVICE_SESSION_DISPATCH',
      'session_id',v_session.id,
      'user_id',v_session.user_id,
      'device_id',v_session.device_id,
      'authorization_id',v_session.device_authorization_id,
      'binding_id',v_session.binding_id,
      'token_hash',encode(p_token_hash,'hex')
    )::text,true
  );
  return reservations_private.mutate_scoped(
    v_session.device_id,p_operation,p_args
  );
end $$;

revoke all on function
  platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)
from public,anon,authenticated;
grant execute on function
  platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)
to service_role;

alter function reservations_private.mutate_scoped(uuid,text,jsonb)
  rename to mutate_scoped_before_participant_booking_type_edit;

create function reservations_private.mutate_scoped(
  p_device_id uuid,
  p_operation text,
  p_args jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_context jsonb;
  v_replay jsonb;
  v_result jsonb;
  v_booking reservations.bookings%rowtype;
  v_type reservations.booking_types%rowtype;
  v_actor uuid;
  v_revision bigint;
  v_operation_id uuid:=(p_args->>'p_operation_id')::uuid;
begin
  if p_operation<>'update_participant_booking' then
    return reservations_private.mutate_scoped_before_participant_booking_type_edit(
      p_device_id,p_operation,p_args
    );
  end if;

  if p_args is null or jsonb_typeof(p_args)<>'object' or p_args ?| array[
    'organization_id','p_organization_id','scope_partition_id',
    'p_scope_partition_id','device_id','p_device_id','actor_user_id',
    'p_actor_user_id','actor_device_id','p_actor_device_id'
  ] then
    raise exception 'RESERVATIONS_SCOPE_OVERRIDE_DENIED' using errcode='42501';
  end if;

  perform platform_private.require_exact_jsonb_keys(p_args,array[
    'p_operation_id','p_booking_id','p_expected_revision','p_booking_type_id',
    'p_full_name','p_phone','p_age','p_church','p_governorate',
    'p_city_or_village','p_service_sector','p_service_sector_other','p_notes'
  ]);
  v_context:=reservations_private.resolve_booking_scope(
    p_device_id,(p_args->>'p_booking_id')::uuid,'reservations.booking.update'
  );
  v_actor:=(v_context->>'actorUserId')::uuid;
  v_replay:=reservations_private.begin_operation(
    v_operation_id,v_context,p_operation,p_args
  );
  if v_replay is not null then return v_replay; end if;

  select * into v_booking
  from reservations.bookings
  where id=(v_context->>'bookingId')::uuid
    and event_id=(v_context->>'eventId')::uuid
    and scope_partition_id=(v_context->>'scopePartitionId')::uuid
    and organization_id is not distinct from
      nullif(v_context->>'organizationId','')::uuid
  for update;
  if not found then
    raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002';
  end if;
  if v_booking.revision<>(p_args->>'p_expected_revision')::bigint then
    raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001';
  end if;

  select * into v_type
  from reservations.booking_types
  where id=(p_args->>'p_booking_type_id')::uuid
    and event_id=v_booking.event_id
    and scope_partition_id=v_booking.scope_partition_id
    and organization_id is not distinct from v_booking.organization_id
  for key share;
  if not found then
    raise exception 'RESERVATIONS_BOOKING_TYPE_EVENT_MISMATCH'
      using errcode='22023';
  end if;
  if v_type.id<>v_booking.booking_type_id and not v_type.active then
    raise exception 'RESERVATIONS_BOOKING_TYPE_INACTIVE' using errcode='22023';
  end if;

  update reservations.participants
  set full_name=btrim(p_args->>'p_full_name'),
      phone=btrim(p_args->>'p_phone'),
      age=(p_args->>'p_age')::integer,
      church=coalesce(p_args->>'p_church',''),
      governorate=btrim(p_args->>'p_governorate'),
      city_or_village=coalesce(p_args->>'p_city_or_village',''),
      service_sector=p_args->>'p_service_sector',
      service_sector_other=nullif(btrim(p_args->>'p_service_sector_other'),''),
      notes=nullif(p_args->>'p_notes',''),
      revision=revision+1,
      updated_at=statement_timestamp(),
      updated_by=v_actor
  where id=v_booking.participant_id
    and scope_partition_id=v_booking.scope_partition_id
    and organization_id is not distinct from v_booking.organization_id;
  if not found then
    raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002';
  end if;

  update reservations.bookings
  set booking_type_id=v_type.id,
      booking_type_name_snapshot=v_type.name,
      price_snapshot=v_type.price,
      notes=nullif(p_args->>'p_notes',''),
      revision=revision+1,
      updated_at=statement_timestamp(),
      updated_by=v_actor
  where id=v_booking.id
    and event_id=v_booking.event_id
    and scope_partition_id=v_booking.scope_partition_id
    and organization_id is not distinct from v_booking.organization_id
  returning revision into v_revision;

  v_result:=jsonb_build_object(
    'bookingId',v_booking.id,
    'bookingTypeId',v_type.id,
    'revision',v_revision
  );
  perform reservations_private.audit(
    v_context,'booking.updated','booking',v_booking.id,v_operation_id,
    to_jsonb(v_booking),v_result
  );
  return reservations_private.complete_operation(
    v_operation_id,v_context,p_operation,p_args,v_result
  );
end $$;

revoke all on function
  reservations_private.mutate_scoped(uuid,text,jsonb)
from public,anon,authenticated,service_role;
grant execute on function
  reservations_private.mutate_scoped(uuid,text,jsonb)
to postgres;
