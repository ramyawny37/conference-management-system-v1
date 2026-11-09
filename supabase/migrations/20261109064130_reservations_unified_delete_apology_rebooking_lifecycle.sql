-- Unified booking lifecycle for standalone events.
-- Delete removes a booking from event operations while preserving immutable financial history.
-- Active duplicates are blocked; apologized/deleted history does not block a new booking.

alter table reservations.bookings
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references platform.profiles(user_id),
  add column if not exists deleted_by_device_id uuid references platform.devices(id);

alter table reservations.bookings drop constraint if exists bookings_lifecycle_status_check;
alter table reservations.bookings drop constraint if exists reservations_booking_apology_lifecycle_check;
alter table reservations.bookings
  add constraint bookings_lifecycle_status_check check (lifecycle_status in ('active','apologized','deleted')),
  add constraint reservations_booking_apology_lifecycle_check check (
    (lifecycle_status='active' and apologized_at is null and apology_reason is null
      and apologized_by is null and apologized_by_device_id is null
      and deleted_at is null and deleted_by is null and deleted_by_device_id is null)
    or
    (lifecycle_status='apologized' and apologized_at is not null
      and nullif(btrim(apology_reason),'') is not null
      and apologized_by is not null and apologized_by_device_id is not null
      and deleted_at is null and deleted_by is null and deleted_by_device_id is null)
    or
    (lifecycle_status='deleted' and deleted_at is not null
      and deleted_by is not null and deleted_by_device_id is not null
      and ((apologized_at is null and apology_reason is null and apologized_by is null and apologized_by_device_id is null)
        or (apologized_at is not null and nullif(btrim(apology_reason),'') is not null
          and apologized_by is not null and apologized_by_device_id is not null)))
  );

create or replace view reservations.bookings_operational with (security_invoker=true) as
select booking.id,booking.booking_number,booking.participant_id,booking.event_id,
 booking.booking_type_id,booking.booking_type_name_snapshot,booking_type.price as price_snapshot,
 booking.attendance_segments_snapshot,booking.notes,booking.revision,booking.created_at,booking.updated_at,
 booking.created_by,booking.updated_by,booking.scope_partition_id,booking.lifecycle_status,
 booking.apologized_at,booking.apology_reason,booking.apologized_by,booking.apologized_by_device_id,
 booking.deleted_at,booking.deleted_by,booking.deleted_by_device_id
from reservations.bookings booking
join reservations.booking_types booking_type on booking_type.id=booking.booking_type_id
 and booking_type.event_id=booking.event_id and booking_type.scope_partition_id=booking.scope_partition_id;
revoke all on reservations.bookings_operational from public,anon,authenticated,service_role;

do $migration$
declare d text; start_pos int; end_pos int;
 old_guard text := $old$
  if exists (
    select 1 from reservations.bookings existing_booking
    join reservations.participants existing_participant
      on existing_participant.id=existing_booking.participant_id
     and existing_participant.scope_partition_id=existing_booking.scope_partition_id
    where existing_booking.scope_partition_id=v_event.scope_partition_id
      and existing_booking.event_id=v_event.id
      and existing_participant.person_id=v_person_id
  ) then
    raise exception 'RESERVATIONS_PERSON_ALREADY_REGISTERED_IN_EVENT' using errcode='23505';
  end if;
$old$;
 new_guard text := $new$
  if exists (
    select 1 from reservations.bookings existing_booking
    join reservations.participants existing_participant
      on existing_participant.id=existing_booking.participant_id
     and existing_participant.scope_partition_id=existing_booking.scope_partition_id
    where existing_booking.scope_partition_id=v_event.scope_partition_id
      and existing_booking.event_id=v_event.id
      and existing_participant.person_id=v_person_id
      and existing_booking.lifecycle_status='active'
  ) then
    raise exception 'RESERVATIONS_PERSON_ALREADY_REGISTERED_IN_EVENT' using errcode='23505';
  end if;
$new$;
 new_delete text := $delete$
 if p_operation='delete_booking' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_expected_revision']);
  v_context:=reservations_private.resolve_booking_scope(p_device_id,(p_args->>'p_booking_id')::uuid,'reservations.booking.delete');
  v_actor:=(v_context->>'actorUserId')::uuid;
  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args);
  if v_replay is not null then return v_replay; end if;
  select * into v_booking from reservations.bookings where id=(v_context->>'bookingId')::uuid
   and event_id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for update;
  if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002'; end if;
  if v_booking.revision<>(p_args->>'p_expected_revision')::bigint then raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001'; end if;
  if v_booking.lifecycle_status='deleted' then raise exception 'RESERVATIONS_BOOKING_ALREADY_DELETED' using errcode='55000'; end if;
  if exists(select 1 from reservations.events e join reservations.participants p on p.id=v_booking.participant_id
    and p.scope_partition_id=v_booking.scope_partition_id join public.conference_participations cp
    on cp.conference_id=e.conference_id and cp.person_id=p.person_id where e.id=v_booking.event_id
    and e.scope_partition_id=v_booking.scope_partition_id and e.scope_type='conference')
  then raise exception 'RESERVATIONS_CONFERENCE_PERSON_MANUAL_ACTION_REQUIRED' using errcode='55000'; end if;

  if v_booking.lifecycle_status='active' and not exists(select 1 from reservations.booking_cancellation_settlements s
    where s.booking_id=v_booking.id and s.scope_partition_id=v_booking.scope_partition_id) then
   insert into reservations.booking_cancellation_settlements(scope_partition_id,booking_id,person_id,collected_amount,
    non_refundable_amount,refunded_amount,credit_amount,pending_refund_amount,reason,created_by,created_by_device_id,operation_id)
   select v_booking.scope_partition_id,v_booking.id,p.person_id,coalesce(pay.collected,0),0,0,0,coalesce(pay.collected,0),
    'حذف من الفعالية',v_actor,p_device_id,v_operation_id
   from reservations.participants p
   left join lateral(select sum(z.amount) collected from reservations.payments z where z.booking_id=v_booking.id
    and z.scope_partition_id=v_booking.scope_partition_id and z.status='active') pay on true
   where p.id=v_booking.participant_id and p.scope_partition_id=v_booking.scope_partition_id;
  end if;

  update reservations.bookings set lifecycle_status='deleted',deleted_at=statement_timestamp(),deleted_by=v_actor,
   deleted_by_device_id=p_device_id,revision=revision+1,updated_at=statement_timestamp(),updated_by=v_actor
  where id=v_booking.id and event_id=v_booking.event_id and scope_partition_id=v_booking.scope_partition_id
  returning revision into v_revision;
  v_result:=jsonb_build_object('bookingId',v_booking.id,'deleted',true,'status','deleted','revision',v_revision);
  perform reservations_private.audit(v_context,'booking.deleted','booking',v_booking.id,v_operation_id,to_jsonb(v_booking),v_result);
  return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
$delete$;
begin
 d:=pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure);
 if position('and existing_booking.lifecycle_status=''active''' in d)=0 then
   if (length(d)-length(replace(d,old_guard,'')))/length(old_guard)<>1 then raise exception 'RESERVATIONS_DUPLICATE_GUARD_CONTRACT_DRIFT'; end if;
   d:=replace(d,old_guard,new_guard);
 end if;
 start_pos:=position(' if p_operation=''delete_booking'' then' in d);
 end_pos:=position(' if p_operation=''record_payment'' then' in d);
 if start_pos=0 or end_pos=0 or end_pos<=start_pos then raise exception 'RESERVATIONS_DELETE_BRANCH_CONTRACT_DRIFT'; end if;
 d:=substring(d from 1 for start_pos-1)||new_delete||substring(d from end_pos);
 execute d;
end;
$migration$;
