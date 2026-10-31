begin;

alter table reservations.event_periods drop constraint if exists reservations_event_periods_kind_check;
alter table reservations.booking_types drop constraint if exists reservations_booking_types_eligible_attendance_segments_check;
alter table reservations.bookings drop constraint if exists reservations_bookings_attendance_segments_snapshot_check;
alter table reservations.attendance_records drop constraint if exists reservations_attendance_records_segment_check;

alter table reservations.event_periods
  add constraint reservations_event_periods_kind_format_check
  check(kind=btrim(kind) and kind~'^[a-z][a-z0-9_-]{0,39}$'),
  add constraint reservations_event_periods_event_kind_unique unique(event_id,kind) deferrable initially deferred;

alter table reservations.attendance_records
  add constraint reservations_attendance_records_segment_format_check
  check(segment=btrim(segment) and segment~'^[a-z][a-z0-9_-]{0,39}$');

create or replace function reservations_private.validate_dynamic_attendance_segments()
returns trigger language plpgsql security definer set search_path='' as $function$
declare v_event_id uuid; v_segments text[];
begin
  if tg_table_name='booking_types' then
    v_event_id:=new.event_id; v_segments:=new.eligible_attendance_segments;
  elsif tg_table_name='bookings' then
    v_event_id:=new.event_id; v_segments:=new.attendance_segments_snapshot;
  else
    select booking.event_id,booking.attendance_segments_snapshot into v_event_id,v_segments
    from reservations.bookings booking
    where booking.id=new.booking_id and booking.scope_partition_id=new.scope_partition_id;
    if not found or not(new.segment=any(v_segments)) then raise exception 'RESERVATIONS_ATTENDANCE_SEGMENT_INELIGIBLE' using errcode='22023';end if;
    v_segments:=array[new.segment];
  end if;
  if v_segments is null then raise exception 'RESERVATIONS_EVENT_PERIOD_REQUIRED' using errcode='23514';end if;
  if cardinality(v_segments)=0 and tg_table_name<>'attendance_records' then return new;end if;
  if cardinality(v_segments)=0
     or cardinality(v_segments)<>(select count(distinct segment) from unnest(v_segments) requested(segment))
     or exists(
    select 1 from unnest(v_segments) requested(segment)
    where not exists(select 1 from reservations.event_periods period where period.event_id=v_event_id and period.kind=requested.segment)
  ) then
    raise exception 'RESERVATIONS_EVENT_PERIOD_REQUIRED' using errcode='23514';
  end if;
  return new;
end $function$;

create or replace function reservations_private.protect_dynamic_attendance_period()
returns trigger language plpgsql security definer set search_path='' as $function$
begin
  if exists(
    select 1 from reservations.booking_types booking_type
    where booking_type.event_id=old.event_id and old.kind=any(booking_type.eligible_attendance_segments)
  ) then raise exception 'RESERVATIONS_EVENT_PERIOD_IN_USE' using errcode='23503';end if;
  return old;
end $function$;

revoke all on function reservations_private.validate_dynamic_attendance_segments() from public,anon,authenticated,service_role;
revoke all on function reservations_private.protect_dynamic_attendance_period() from public,anon,authenticated,service_role;

drop trigger if exists reservations_booking_type_dynamic_segments on reservations.booking_types;
create trigger reservations_booking_type_dynamic_segments before insert or update of event_id,eligible_attendance_segments on reservations.booking_types
for each row execute function reservations_private.validate_dynamic_attendance_segments();

drop trigger if exists reservations_booking_dynamic_segments on reservations.bookings;
create trigger reservations_booking_dynamic_segments before insert or update of event_id,attendance_segments_snapshot on reservations.bookings
for each row execute function reservations_private.validate_dynamic_attendance_segments();

drop trigger if exists reservations_attendance_dynamic_segment on reservations.attendance_records;
create trigger reservations_attendance_dynamic_segment before insert or update of booking_id,segment on reservations.attendance_records
for each row execute function reservations_private.validate_dynamic_attendance_segments();

drop trigger if exists reservations_event_period_dynamic_delete_guard on reservations.event_periods;
create trigger reservations_event_period_dynamic_delete_guard before delete on reservations.event_periods
for each row execute function reservations_private.protect_dynamic_attendance_period();

do $rewrite$
declare definition text;
begin
  definition:=pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure);
  if position('p_args->>''p_kind'' not in (''conference'',''caravans'')' in definition)=0 then
    raise exception 'RESERVATIONS_PERIOD_MUTATION_SHAPE_CHANGED' using errcode='55000';
  end if;
  definition:=replace(definition,
    'p_args->>''p_kind'' not in (''conference'',''caravans'') or ',
    'coalesce(p_args->>''p_kind'','''')!~''^[a-z][a-z0-9_-]{0,39}$'' or ');
  execute definition;
end $rewrite$;

do $contract$
begin
  if to_regprocedure('reservations_private.validate_dynamic_attendance_segments()') is null
     or not exists(select 1 from pg_constraint where conname='reservations_event_periods_event_kind_unique') then
    raise exception 'RESERVATIONS_DYNAMIC_PERIOD_CONTRACT_INCOMPLETE' using errcode='55000';
  end if;
end $contract$;

commit;
