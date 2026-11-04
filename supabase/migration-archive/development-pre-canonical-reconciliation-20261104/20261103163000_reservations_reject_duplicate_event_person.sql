-- Enforce one new booking per canonical person and event in the existing atomic
-- reservation writer. The event row is already locked FOR UPDATE before this
-- check, serializing competing create_booking operations for the same event.
-- Historical duplicate bookings and their financial records are preserved.
do $migration$
declare
  v_definition text;
  v_needle text := 'end if; insert into reservations.participants(scope_partition_id,person_id,full_name';
  v_guard text := $guard$end if;
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
  insert into reservations.participants(scope_partition_id,person_id,full_name$guard$;
begin
  v_definition:=pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure);
  if (length(v_definition)-length(replace(v_definition,v_needle,'')))/length(v_needle)<>1 then
    raise exception 'RESERVATIONS_CREATE_BOOKING_CONTRACT_DRIFT';
  end if;
  execute replace(v_definition,v_needle,v_guard);
end;
$migration$;
