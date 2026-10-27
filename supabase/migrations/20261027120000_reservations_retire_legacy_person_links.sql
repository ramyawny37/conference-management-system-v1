begin;
do $cutover$
declare
 v_mutate text;
 v_read text;
 v_old text := 'if exists(select 1 from reservations.conference_person_links where booking_id=v_booking.id) then';
 v_new text := 'if exists(select 1 from reservations.events e join reservations.participants p on p.id=v_booking.participant_id and p.scope_partition_id=v_booking.scope_partition_id join public.conference_participations cp on cp.conference_id=e.conference_id and cp.person_id=p.person_id where e.id=v_booking.event_id and e.scope_partition_id=v_booking.scope_partition_id and e.scope_type=''conference'') then';
begin
 select pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure) into v_mutate;
 select pg_get_functiondef('reservations_private.read_scoped(uuid,text,jsonb)'::regprocedure) into v_read;
 if position(v_old in v_mutate)=0 or position('v_link reservations.conference_person_links%rowtype;' in v_read)=0 then
  raise exception 'RESERVATIONS_LEGACY_LINK_CUTOVER_SOURCE_MISMATCH';
 end if;
 v_mutate:=replace(v_mutate,v_old,v_new);
 v_read:=replace(v_read,'v_link reservations.conference_person_links%rowtype; ','');
 execute v_mutate;
 execute v_read;
 if exists(select 1 from pg_proc p where p.prokind='f' and pg_get_functiondef(p.oid) like '%conference_person_links%') then
  raise exception 'RESERVATIONS_LEGACY_LINK_FUNCTION_REMAINS';
 end if;
 if exists(select 1 from reservations.conference_person_links) then
  raise exception 'RESERVATIONS_LEGACY_LINK_HAS_DATA';
 end if;
 drop table reservations.conference_person_links;
end
$cutover$;
commit;