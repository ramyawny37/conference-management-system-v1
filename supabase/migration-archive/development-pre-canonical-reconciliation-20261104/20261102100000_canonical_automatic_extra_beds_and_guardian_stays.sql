begin;

alter table public.conference_accommodation_occupancies
  add column if not exists extra_bed_source text;

update public.conference_accommodation_occupancies
set extra_bed_source='manual'
where bed_type='extra' and extra_bed_source is null;

alter table public.conference_accommodation_occupancies
  drop constraint if exists conference_accommodation_occupancies_extra_bed_source_check;
alter table public.conference_accommodation_occupancies
  add constraint conference_accommodation_occupancies_extra_bed_source_check
  check ((bed_type='extra' and extra_bed_source in('manual','automatic'))
      or (bed_type<>'extra' and extra_bed_source is null));

create or replace function platform_private.set_conference_automatic_extra_bed_source()
returns trigger language plpgsql security definer set search_path='' as $function$
declare participation public.conference_participations%rowtype;
begin
  if new.bed_type<>'extra' then new.extra_bed_source:=null; return new; end if;
  if tg_op='UPDATE' and new.bed_type=old.bed_type
     and new.participation_id is not distinct from old.participation_id
     and old.extra_bed_source is not null then
    new.extra_bed_source:=old.extra_bed_source; return new;
  end if;
  select * into participation from public.conference_participations
  where id=new.participation_id and conference_id=new.conference_id;
  new.extra_bed_source:=case
    when participation.guardian_participation_id is not null
      and new.extra_bed_person_type='child' then 'automatic'
    else 'manual' end;
  return new;
end $function$;

drop trigger if exists conference_accommodation_extra_bed_source on public.conference_accommodation_occupancies;
create trigger conference_accommodation_extra_bed_source
before insert or update of conference_id,participation_id,bed_type,extra_bed_person_type
on public.conference_accommodation_occupancies for each row
execute function platform_private.set_conference_automatic_extra_bed_source();

create or replace function platform_private.enforce_linked_child_guardian_stay()
returns trigger language plpgsql security definer set search_path='' as $function$
declare
  child public.conference_participations%rowtype;
  guardian public.conference_participations%rowtype;
  guardian_stay public.conference_accommodation_occupancies%rowtype;
  conference_days integer;
begin
  select * into child from public.conference_participations
  where id=new.participation_id and conference_id=new.conference_id;
  if not found or child.guardian_participation_id is null then return new; end if;
  select * into guardian from public.conference_participations
  where id=child.guardian_participation_id and conference_id=new.conference_id and status='active';
  if not found then raise exception 'ACCOMMODATION_ACTIVE_GUARDIAN_REQUIRED' using errcode='23514'; end if;
  conference_days:=platform_private.conference_accommodation_duration(new.conference_id);
  if new.bed_type='shared' then
    select * into guardian_stay from public.conference_accommodation_occupancies stay
    where stay.conference_id=new.conference_id and stay.participation_id=guardian.id
      and stay.room_id=new.room_id and stay.arrival_day=new.arrival_day
      and stay.leave_day is not distinct from new.leave_day
    order by stay.id limit 1 for key share;
    if not found then raise exception 'ACCOMMODATION_SHARED_CHILD_GUARDIAN_STAY_REQUIRED' using errcode='23514'; end if;
  else
    select * into guardian_stay from public.conference_accommodation_occupancies stay
    where stay.conference_id=new.conference_id and stay.participation_id=guardian.id
      and stay.arrival_day<=new.arrival_day
      and coalesce(stay.leave_day,conference_days+1)>=coalesce(new.leave_day,conference_days+1)
    order by stay.arrival_day desc,stay.id limit 1 for key share;
    if not found then raise exception 'ACCOMMODATION_CHILD_GUARDIAN_STAY_REQUIRED' using errcode='23514'; end if;
  end if;
  if new.bed_type='extra' and new.extra_bed_person_type is distinct from 'child' then
    raise exception 'ACCOMMODATION_CHILD_BED_TYPE_INVALID' using errcode='23514';
  end if;
  if new.bed_type<>'extra' and new.extra_bed_person_type is not null then
    raise exception 'ACCOMMODATION_CHILD_BED_TYPE_INVALID' using errcode='23514';
  end if;
  if new.bed_type='shared' then
    if tg_op='INSERT' then new.arrived_at:=guardian_stay.arrived_at;new.arrived_by:=guardian_stay.arrived_by;
    elsif new.arrived_at is distinct from guardian_stay.arrived_at or new.arrived_by is distinct from guardian_stay.arrived_by then
      raise exception 'ACCOMMODATION_CHILD_ARRIVAL_INHERITED' using errcode='23514'; end if;
  end if;
  return new;
end $function$;

drop trigger if exists conference_accommodation_shared_child_guardian on public.conference_accommodation_occupancies;
drop trigger if exists conference_accommodation_linked_child_guardian on public.conference_accommodation_occupancies;
create trigger conference_accommodation_linked_child_guardian
before insert or update of conference_id,room_id,participation_id,arrival_day,leave_day,bed_type,extra_bed_person_type,arrived_at,arrived_by
on public.conference_accommodation_occupancies for each row
execute function platform_private.enforce_linked_child_guardian_stay();

create or replace function platform_private.conference_room_has_capacity(
  p_conference uuid,p_room uuid,p_bed text,p_arrival integer,p_leave integer,
  p_exclude_occupancy uuid default null
) returns boolean language sql stable security definer set search_path='' as $function$
  select p_bed='shared'
    or (p_bed='extra' and exists(
      select 1 from public.conference_accommodation_occupancies excluded
      where excluded.id=p_exclude_occupancy and excluded.extra_bed_source='automatic'))
    or not exists(
      select 1
      from generate_series(p_arrival,coalesce(p_leave,platform_private.conference_accommodation_duration(p_conference)+1)-1) night(day)
      cross join lateral(
        select count(*)::integer used
        from public.conference_accommodation_occupancies occupancy
        where occupancy.conference_id=p_conference and occupancy.room_id=p_room
          and occupancy.bed_type=p_bed and occupancy.id is distinct from p_exclude_occupancy
          and (p_bed<>'extra' or occupancy.extra_bed_source='manual')
          and occupancy.arrival_day<=night.day
          and coalesce(occupancy.leave_day,platform_private.conference_accommodation_duration(p_conference)+1)>night.day
      ) usage
      join public.conference_accommodation_rooms room on room.id=p_room
      join public.conference_room_assignments assignment
        on assignment.conference_id=p_conference and assignment.room_id=room.id
      where usage.used>=case when p_bed='base' then room.base_capacity else assignment.extra_bed_capacity end)
$function$;

do $runtime_patches$
declare definition text;
begin
  definition:=pg_get_functiondef('public.assign_conference_accommodation(uuid,uuid,uuid,uuid,integer,integer,text,text)'::regprocedure);
  if position('if not platform_private.conference_room_has_capacity(p_conference,p_room,p_bed,p_arrival,p_leave,null) then' in definition)=0 then
    raise exception 'AUTOMATIC_EXTRA_ASSIGN_SHAPE_CHANGED' using errcode='55000'; end if;
  definition:=replace(definition,
    'if not platform_private.conference_room_has_capacity(p_conference,p_room,p_bed,p_arrival,p_leave,null) then',
    'if not (p_bed=''extra'' and p_extra_type=''child'' and participation.guardian_participation_id is not null) and not platform_private.conference_room_has_capacity(p_conference,p_room,p_bed,p_arrival,p_leave,null) then');
  execute definition;

  definition:=pg_get_functiondef('public.move_conference_accommodation(uuid,uuid,uuid,bigint,uuid,integer,integer,text,text)'::regprocedure);
  if position('if not platform_private.conference_room_has_capacity(p_conference,p_room,p_bed,p_arrival,p_leave,case when historical then null else p_occupancy end) then' in definition)=0 then
    raise exception 'AUTOMATIC_EXTRA_MOVE_SHAPE_CHANGED' using errcode='55000'; end if;
  definition:=replace(definition,
    'if not platform_private.conference_room_has_capacity(p_conference,p_room,p_bed,p_arrival,p_leave,case when historical then null else p_occupancy end) then',
    'if not (p_bed=''extra'' and p_extra_type=''child'' and participation.guardian_participation_id is not null) and not platform_private.conference_room_has_capacity(p_conference,p_room,p_bed,p_arrival,p_leave,case when historical then null else p_occupancy end) then');
  execute definition;

  definition:=pg_get_functiondef('public.save_conference_accommodation_room_draft(uuid,uuid,uuid,uuid,bigint,bigint,jsonb,jsonb,jsonb,jsonb)'::regprocedure);
  if position('and o.bed_type=''extra'' and o.arrival_day<=d.day' in definition)=0 then
    raise exception 'MANUAL_EXTRA_CAPACITY_SHAPE_CHANGED' using errcode='55000'; end if;
  definition:=replace(definition,'and o.bed_type=''extra'' and o.arrival_day<=d.day',
    'and o.bed_type=''extra'' and o.extra_bed_source=''manual'' and o.arrival_day<=d.day');
  execute definition;

  definition:=pg_get_functiondef('platform_private.sync_guardian_linked_child_stays()'::regprocedure);
  if position('if not platform_private.conference_room_has_capacity(new.conference_id,new.room_id,linked.bed_type' in definition)=0
     or position('extra_bed_person_type,arrived_at,arrived_by,created_by,updated_by' in definition)=0 then
    raise exception 'AUTOMATIC_EXTRA_GUARDIAN_SYNC_SHAPE_CHANGED' using errcode='55000'; end if;
  definition:=replace(definition,
    'if not platform_private.conference_room_has_capacity(new.conference_id,new.room_id,linked.bed_type',
    'if linked.extra_bed_source is distinct from ''automatic'' and not platform_private.conference_room_has_capacity(new.conference_id,new.room_id,linked.bed_type');
  definition:=replace(definition,
    'extra_bed_person_type,arrived_at,arrived_by,created_by,updated_by',
    'extra_bed_person_type,extra_bed_source,arrived_at,arrived_by,created_by,updated_by');
  definition:=replace(definition,
    'linked.bed_type,linked.extra_bed_person_type,new.arrived_at,new.arrived_by,',
    'linked.bed_type,linked.extra_bed_person_type,linked.extra_bed_source,new.arrived_at,new.arrived_by,');
  execute definition;

  definition:=pg_get_functiondef('public.get_conference_accommodation(uuid,uuid)'::regprocedure);
  if position('''extraBedPersonType'',o.extra_bed_person_type,''participationId''' in definition)=0 then
    raise exception 'AUTOMATIC_EXTRA_PROJECTION_SHAPE_CHANGED' using errcode='55000'; end if;
  definition:=replace(definition,
    '''extraBedPersonType'',o.extra_bed_person_type,''participationId''',
    '''extraBedPersonType'',o.extra_bed_person_type,''extraBedSource'',o.extra_bed_source,''participationId''');
  execute definition;
end $runtime_patches$;

revoke all on function platform_private.set_conference_automatic_extra_bed_source() from public,anon,authenticated,service_role;
revoke all on function platform_private.enforce_linked_child_guardian_stay() from public,anon,authenticated,service_role;
revoke all on function platform_private.conference_room_has_capacity(uuid,uuid,text,integer,integer,uuid) from public,anon,authenticated,service_role;

do $contract$
declare definition text;
begin
  definition:=pg_get_functiondef('public.assign_conference_accommodation(uuid,uuid,uuid,uuid,integer,integer,text,text)'::regprocedure);
  if position('participation.guardian_participation_id is not null' in definition)=0 then raise exception 'AUTOMATIC_EXTRA_ASSIGN_INCOMPLETE'; end if;
  definition:=pg_get_functiondef('public.get_conference_accommodation(uuid,uuid)'::regprocedure);
  if position('''extraBedSource'',o.extra_bed_source' in definition)=0 then raise exception 'AUTOMATIC_EXTRA_PROJECTION_INCOMPLETE'; end if;
end $contract$;

commit;
