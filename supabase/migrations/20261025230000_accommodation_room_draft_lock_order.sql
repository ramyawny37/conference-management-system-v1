begin;
do $reconcile$
declare d text;marker text;locked text;
begin
 d:=pg_get_functiondef('public.save_conference_accommodation_room_draft(uuid,uuid,uuid,uuid,bigint,bigint,jsonb,jsonb)'::regprocedure);
 if position('conference_participations where conference_id=p_conference' in d)=0 then
  marker:='select * into room_assignment from public.conference_room_assignments';
  locked:='perform 1 from public.conference_participations where conference_id=p_conference and id in(select (value->>''participationId'')::uuid from jsonb_array_elements(p_assignments)) order by id for update;'||chr(10)||' select * into room_assignment from public.conference_room_assignments';
  if position(marker in d)=0 then raise exception 'ACCOMMODATION_ROOM_DRAFT_LOCK_MARKER_MISSING';end if;
  execute replace(d,marker,locked);
 end if;
end $reconcile$;
commit;
