begin;
do $fix$
declare definition text;
begin
 select pg_get_functiondef('public.add_conference_guardian_child_accommodation(uuid,uuid,uuid,jsonb)'::regprocedure) into definition;
 if position('room_id=room_id' in definition)=0 or position('person_id=person_id' in definition)=0 then
  raise exception 'GUARDIAN_CHILD_RPC_SHAPE_CHANGED';
 end if;
 definition:=replace(definition,'from public.conference_accommodation_occupancies where conference_id=p_conference and room_id=room_id and participation_id=guardian.id','from public.conference_accommodation_occupancies where conference_id=p_conference and public.conference_accommodation_occupancies.room_id=room_id and participation_id=guardian.id');
 definition:=replace(definition,'from public.conference_participations where conference_id=p_conference and person_id=person_id and status=','from public.conference_participations where conference_id=p_conference and public.conference_participations.person_id=person_id and status=');
 execute definition;
end $fix$;
commit;
