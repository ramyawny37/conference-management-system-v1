begin;
do $$
declare
  v_definition text;
begin
  if to_regprocedure('reservations_private.link_booking_to_canonical_participation(uuid,uuid,jsonb)') is null then
    raise exception 'RESERVATIONS_CANONICAL_LINK_MISSING' using errcode='55000';
  end if;
  select pg_get_functiondef('reservations.mutate_pre_authorization_architecture_reconciliation(uuid,text,jsonb)'::regprocedure)
    into v_definition;
  if (length(v_definition)-length(replace(v_definition,
    'reservations_private.project_booking_to_conference(','')))
    /length('reservations_private.project_booking_to_conference(') <> 1 then
    raise exception 'RESERVATIONS_WRITE_CUTOVER_PRECONDITION_FAILED' using errcode='55000';
  end if;
  execute replace(v_definition,
    'reservations_private.project_booking_to_conference(',
    'reservations_private.link_booking_to_canonical_participation(');
end $$;
commit;
