begin;

-- Keep the historical booking row intact, but make every operational reader
-- resolve its price from the booking type owned by the same event and scope.
-- The price_snapshot column is exposed only as a backwards-compatible JSON
-- field name; its operational value comes exclusively from booking_types.price.
create or replace view reservations.bookings_operational
with (security_invoker=true) as
select
  booking.id,
  booking.booking_number,
  booking.participant_id,
  booking.event_id,
  booking.booking_type_id,
  booking.booking_type_name_snapshot,
  booking_type.price as price_snapshot,
  booking.attendance_segments_snapshot,
  booking.notes,
  booking.revision,
  booking.created_at,
  booking.updated_at,
  booking.created_by,
  booking.updated_by,
  booking.scope_partition_id
from reservations.bookings booking
join reservations.booking_types booking_type
  on booking_type.id=booking.booking_type_id
 and booking_type.event_id=booking.event_id
 and booking_type.scope_partition_id=booking.scope_partition_id;

revoke all on reservations.bookings_operational
  from public,anon,authenticated,service_role;

do $migration$
declare
  definition text;
  rewritten text;
  source_count integer;
begin
  definition:=pg_get_functiondef(
    'reservations_private.read_scoped(uuid,text,jsonb)'::regprocedure
  );
  source_count:=(length(definition)-length(replace(
    definition,'reservations.bookings b',''
  )))/length('reservations.bookings b');
  if source_count<1 then
    raise exception 'RESERVATIONS_CANONICAL_PRICING_READ_CONTRACT_DRIFT';
  end if;
  rewritten:=replace(
    definition,
    'reservations.bookings b',
    'reservations.bookings_operational b'
  );
  if position('reservations.bookings b' in rewritten)>0 then
    raise exception 'RESERVATIONS_CANONICAL_PRICING_READ_REWRITE_INCOMPLETE';
  end if;
  execute rewritten;

  definition:=pg_get_functiondef(
    'public.list_conference_participations(uuid,uuid)'::regprocedure
  );
  source_count:=(length(definition)-length(replace(
    definition,'reservations.bookings booking',''
  )))/length('reservations.bookings booking');
  if source_count<>1 then
    raise exception 'RESERVATIONS_CANONICAL_PRICING_PARTICIPATION_CONTRACT_DRIFT';
  end if;
  rewritten:=replace(
    definition,
    'reservations.bookings booking',
    'reservations.bookings_operational booking'
  );
  if position('reservations.bookings booking' in rewritten)>0 then
    raise exception 'RESERVATIONS_CANONICAL_PRICING_PARTICIPATION_REWRITE_INCOMPLETE';
  end if;
  execute rewritten;
end
$migration$;

revoke all on function reservations_private.read_scoped(uuid,text,jsonb)
  from public,anon,authenticated,service_role;
grant execute on function reservations_private.read_scoped(uuid,text,jsonb)
  to postgres;

revoke all on function public.list_conference_participations(uuid,uuid)
  from public,anon,authenticated,service_role;

commit;
