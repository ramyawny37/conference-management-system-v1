-- Move the existing duplicate guard ahead of canonical-person mutation.
-- Preserve the same event-level FOR UPDATE serialization and existing writer.
do $migration$
declare
  d text;
  old_guard text := $g$
  if exists (
    select 1
    from reservations.bookings existing_booking
    join reservations.participants existing_participant
      on existing_participant.id=existing_booking.participant_id
     and existing_participant.scope_partition_id=existing_booking.scope_partition_id
    where existing_booking.scope_partition_id=v_event.scope_partition_id
      and existing_booking.event_id=v_event.id
      and existing_participant.person_id=v_person_id
  ) then
    raise exception 'RESERVATIONS_PERSON_ALREADY_REGISTERED_IN_EVENT'
      using errcode='23505';
  end if;
$g$;
  anchor text := 'else v_person_id:=(p_args->>''p_person_id'')::uuid;';
  updated text;
begin
  d:=pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure);
  if (length(d)-length(replace(d,old_guard,'')))/length(old_guard)<>1
     or (length(d)-length(replace(d,anchor,'')))/length(anchor)<>1 then
    raise exception 'RESERVATIONS_DUPLICATE_GUARD_ORDER_CONTRACT_DRIFT';
  end if;
  updated:=replace(d,old_guard,'');
  updated:=replace(updated,anchor,anchor||old_guard);
  execute updated;
end;
$migration$;