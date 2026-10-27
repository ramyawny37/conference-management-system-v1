-- Development-only canonical integration guard.
-- This migration is intentionally non-destructive and verifies the live schema
-- before a separate reviewed cutover of active Reservations functions.
begin;
do $$
begin
  if to_regclass('public.conference_participations') is null
    or to_regclass('public.conference_accommodation_occupancies') is null
    or to_regclass('reservations.conference_person_links') is null
    or to_regprocedure('reservations_private.link_booking_to_canonical_participation(uuid,uuid,jsonb)') is null
  then
    raise exception 'RESERVATIONS_CANONICAL_FOUNDATION_MISSING' using errcode='55000';
  end if;
end $$;
commit;
