begin;

-- Extend the canonical move operation so a guardian move carries every child
-- currently housed with that guardian, preserving each child's bed properties.
do $patch$
declare
  d text;
  old_decl text;
  new_decl text;
  old_capacity text;
  new_capacity text;
  old_created text;
  new_created text;
  old_return text;
  new_return text;
begin
  d:=pg_get_functiondef('public.move_conference_accommodation(uuid,uuid,uuid,bigint,uuid,integer,integer,text,text)'::regprocedure);

  old_decl:='guardian_stay public.conference_accommodation_occupancies%rowtype;\ndays integer;updated public.conference_accommodation_occupancies%rowtype;created public.conference_accommodation_occupancies%rowtype;historical boolean;effective_day integer;conference_start date;';
  new_decl:='guardian_stay public.conference_accommodation_occupancies%rowtype;\nchild_stay public.conference_accommodation_occupancies%rowtype;\ndays integer;updated public.conference_accommodation_occupancies%rowtype;created public.conference_accommodation_occupancies%rowtype;\nchild_updated public.conference_accommodation_occupancies%rowtype;child_created public.conference_accommodation_occupancies%rowtype;\nchild_results jsonb:=''[]'';historical boolean;effective_day integer;conference_start date;';

  old_capacity:='if not platform_private.conference_room_has_capacity(p_conference,p_room,p_bed,p_arrival,p_leave,case when historical then null else p_occupancy end) then raise exception ''ACCOMMODATION_ROOM_CAPACITY_EXCEEDED'' using errcode=''55000'';end if;';
  new_capacity:=old_capacity||'\n -- Guardian transfers are household transfers: validate every housed child before changing anything.\n if participation.guardian_participation_id is null then\n   for child_stay in select o.* from public.conference_accommodation_occupancies o join public.conference_participations cp on cp.id=o.participation_id where o.conference_id=p_conference and cp.guardian_participation_id=participation.id and o.room_id=current.room_id and o.arrival_day=current.arrival_day and o.leave_day is not distinct from current.leave_day order by o.id for update loop\n     if not platform_private.conference_room_has_capacity(p_conference,p_room,child_stay.bed_type,p_arrival,p_leave,case when historical then null else child_stay.id end) then raise exception ''ACCOMMODATION_ROOM_CAPACITY_EXCEEDED'' using errcode=''55000'';end if;\n   end loop;\n end if;';

  old_created:='created:=updated;\nend if;\n insert into platform.audit_events';
  new_created:='created:=updated;\n end if;\n -- Move the children atomically with the guardian, preserving their bed type and extra-bed designation.\n if participation.guardian_participation_id is null then\n   for child_stay in select o.* from public.conference_accommodation_occupancies o join public.conference_participations cp on cp.id=o.participation_id where o.conference_id=p_conference and cp.guardian_participation_id=participation.id and o.room_id=current.room_id and o.arrival_day=current.arrival_day and o.leave_day is not distinct from current.leave_day and o.id<>current.id order by o.id for update loop\n     if historical then\n       update public.conference_accommodation_occupancies set leave_day=p_arrival,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=child_stay.id returning * into child_updated;\n       insert into public.conference_accommodation_occupancies(conference_id,room_id,participation_id,arrival_day,leave_day,bed_type,extra_bed_person_type,created_by,updated_by) values(p_conference,p_room,child_stay.participation_id,p_arrival,p_leave,child_stay.bed_type,child_stay.extra_bed_person_type,actor,actor) returning * into child_created;\n     else\n       update public.conference_accommodation_occupancies set room_id=p_room,arrival_day=p_arrival,leave_day=p_leave,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=child_stay.id returning * into child_updated;\n       child_created:=child_updated;\n     end if;\n     child_results:=child_results||jsonb_build_array(jsonb_build_object(''occupancyId'',child_created.id,''previousOccupancyId'',case when historical then child_stay.id else null end,''revision'',child_created.revision,''roomId'',child_created.room_id,''arrivalDay'',child_created.arrival_day,''leaveDay'',child_created.leave_day,''bedType'',child_created.bed_type,''extraBedPersonType'',child_created.extra_bed_person_type));\n   end loop;\n end if;\n insert into platform.audit_events';

  old_return:='return jsonb_build_object(''occupancyId'',created.id,''revision'',created.revision,''roomId'',created.room_id,''previousOccupancyId'',case when historical then current.id else null end,''historicalSegmentPreserved'',historical,''arrivalDay'',created.arrival_day,''leaveDay'',created.leave_day);';
  new_return:='return jsonb_build_object(''occupancyId'',created.id,''revision'',created.revision,''roomId'',created.room_id,''previousOccupancyId'',case when historical then current.id else null end,''historicalSegmentPreserved'',historical,''arrivalDay'',created.arrival_day,''leaveDay'',created.leave_day,''childrenMoved'',child_results);';

  if position(old_decl in d)=0 or position(old_capacity in d)=0 or position(old_created in d)=0 or position(old_return in d)=0 then raise exception ''GUARDIAN_MOVE_PATCH_MARKER_MISSING''; end if;
  d:=replace(d,old_decl,new_decl);
  d:=replace(d,old_capacity,new_capacity);
  d:=replace(d,old_created,new_created);
  d:=replace(d,old_return,new_return);
  execute d;
end $patch$;

commit;
