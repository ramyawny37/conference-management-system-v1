begin;
do $$
declare d text; a integer; b integer; replacement text;
begin
 select pg_get_functiondef('reservations_private.read_scoped(uuid,text,jsonb)'::regprocedure) into d;
 a:=position('elsif p_operation=''get_booking_accommodation'' then' in d);
 b:=a+position('elsif p_operation=''get_dashboard_summary'' then' in substring(d from a))-1;
 if a=0 or b<=a then raise exception 'RESERVATIONS_ACCOMMODATION_READ_PRECONDITION_FAILED' using errcode='55000'; end if;
 replacement:=$branch$
 elsif p_operation='get_booking_accommodation' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_booking_id']);
  if v_context->>'scopeType'='standalone' then
   return reservations_private.standalone_accommodation_not_applicable(v_booking_id);
  end if;
  return (
   select jsonb_strip_nulls(jsonb_build_object(
    'bookingId',b.id,'conferenceId',e.conference_id,
    'conferencePersonId',p.person_id,'conferenceParticipationId',cp.id,
    'linked',cp.id is not null,'readyForAccommodation',cp.id is not null,
    'accommodated',o.id is not null,'roomId',r.id,
    'roomNumber',r.room_number,'houseLabel',h.name,'floorLabel',f.name
   ))
   from reservations.bookings b
   join reservations.events e on e.id=b.event_id and e.scope_partition_id=b.scope_partition_id
   join reservations.participants p on p.id=b.participant_id and p.scope_partition_id=b.scope_partition_id
   left join public.conference_participations cp on cp.conference_id=e.conference_id and cp.person_id=p.person_id
   left join lateral (
    select x.id,x.room_id from public.conference_accommodation_occupancies x
    where x.conference_id=e.conference_id and x.participation_id=cp.id
    order by x.arrival_day desc,x.id limit 1
   ) o on true
   left join public.conference_accommodation_rooms r on r.id=o.room_id
   left join public.conference_accommodation_floors f on f.id=r.floor_id
   left join public.conference_accommodation_houses h on h.id=f.house_id
   where b.id=v_booking_id
  );
 $branch$;
 d:=left(d,a-1)||replacement||substring(d from b);
 if position('conference_snapshots' in d)>0 then raise exception 'RESERVATIONS_LEGACY_SNAPSHOT_READ_REMAINS' using errcode='55000'; end if;
 execute d;
end $$;
commit;
