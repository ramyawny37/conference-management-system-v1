do $$
declare
  v_sql text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef('public.replace_conference_accommodation(uuid,uuid,uuid,uuid,bigint,uuid,integer,text,text)'::regprocedure) into v_sql;

  v_old := $m$new_stay public.conference_accommodation_occupancies%rowtype;
 prior_old jsonb;result jsonb;$m$;
  v_new := $m$new_stay public.conference_accommodation_occupancies%rowtype;
 child_stay public.conference_accommodation_occupancies%rowtype;
 prior_old jsonb;result jsonb;$m$;
  if position(v_old in v_sql)=0 then
    raise exception 'guardian replacement migration: declaration marker not found';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := $m$ if p_effective_day=old_stay.arrival_day then
   -- The original row cannot represent a zero-length segment. Its complete
   -- value remains immutable in the audit event; deletion occurs only inside
   -- this transaction and therefore rolls back if the replacement fails.
   delete from public.conference_accommodation_occupancies where id=old_stay.id;
 else
   update public.conference_accommodation_occupancies set leave_day=p_effective_day,
    revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=old_stay.id;
 end if;$m$;
  v_new := $m$ -- Replacing a guardian removes only the children currently housed
 -- under that guardian from accommodation. Their central participation and
 -- guardian relationship remain intact. This is part of the same transaction.
 for child_stay in
   select o.*
   from public.conference_accommodation_occupancies o
   join public.conference_participations cp on cp.id=o.participation_id
   where o.conference_id=p_conference
     and o.room_id=old_stay.room_id
     and cp.guardian_participation_id=old_stay.participation_id
     and o.arrival_day<=p_effective_day
     and p_effective_day<coalesce(o.leave_day,days+1)
     and o.id<>old_stay.id
   order by o.id
   for update
 loop
   if room.key_holder_occupancy_id=child_stay.id then
     update public.conference_accommodation_rooms
       set key_holder_occupancy_id=null,updated_at=statement_timestamp(),updated_by=actor
       where id=room.id;
   end if;
   if p_effective_day=child_stay.arrival_day then
     delete from public.conference_accommodation_occupancies where id=child_stay.id;
   else
     update public.conference_accommodation_occupancies
       set leave_day=p_effective_day,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor
       where id=child_stay.id;
   end if;
 end loop;

 if p_effective_day=old_stay.arrival_day then
   -- The original row cannot represent a zero-length segment. Its complete
   -- value remains immutable in the audit event; deletion occurs only inside
   -- this transaction and therefore rolls back if the replacement fails.
   delete from public.conference_accommodation_occupancies where id=old_stay.id;
 else
   update public.conference_accommodation_occupancies set leave_day=p_effective_day,
    revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=old_stay.id;
 end if;$m$;
  if position(v_old in v_sql)=0 then
    raise exception 'guardian replacement migration: replacement marker not found';
  end if;
  v_sql := replace(v_sql,v_old,v_new);

  execute v_sql;
end $$;
