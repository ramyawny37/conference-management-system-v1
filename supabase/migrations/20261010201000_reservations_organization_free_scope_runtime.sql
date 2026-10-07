begin;
-- Runtime authority is installed before retiring schema columns.
drop function reservations_private.allocate_booking_number(uuid,integer);
create or replace function reservations_private.derive_event_scope_partition()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.scope_type is null then
  if new.conference_id is null then
   new.scope_type:='standalone';
   new.scope_partition_id:=coalesce(new.scope_partition_id,extensions.gen_random_uuid());
  else new.scope_type:='conference';new.scope_partition_id:=new.conference_id;end if;
 elsif new.scope_type='standalone' then
  new.conference_id:=null;
  new.scope_partition_id:=coalesce(new.scope_partition_id,extensions.gen_random_uuid());
 elsif new.scope_type='conference' then
  if new.conference_id is null then raise exception 'RESERVATIONS_CONFERENCE_REQUIRED' using errcode='22023';end if;
  new.scope_partition_id:=new.conference_id;
 else raise exception 'RESERVATIONS_SCOPE_TYPE_INVALID' using errcode='22023';end if;
 return new;
end $$;

create or replace function reservations_private.conference_context(
 p_device_id uuid,p_conference_id uuid,p_permission text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_context jsonb;
begin
 v_context:=public.require_effective_module_permission(p_device_id,'reservations',p_permission,null,null);
 if not exists(select 1 from public.conferences c where c.id=p_conference_id and c.deleted_at is null) then
  raise exception 'RESERVATIONS_CONFERENCE_ACCESS_REQUIRED' using errcode='42501';
 end if;
 return v_context||jsonb_build_object('conferenceId',p_conference_id,'scopeType','conference','scopePartitionId',p_conference_id);
end $$;

create or replace function reservations_private.event_scope_context(
 p_device_id uuid,p_event_id uuid,p_permission text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_event reservations.events%rowtype;v_context jsonb;
begin
 v_context:=public.require_effective_module_permission(p_device_id,'reservations',p_permission,null,null);
 select * into v_event from reservations.events where id=p_event_id;
 if not found then raise exception 'RESERVATIONS_EVENT_NOT_FOUND' using errcode='P0002';end if;
 if v_event.scope_type='conference' then
  v_context:=reservations_private.conference_context(p_device_id,v_event.conference_id,p_permission);
 end if;
 return v_context||jsonb_build_object('scopeType',v_event.scope_type,'scopePartitionId',v_event.scope_partition_id,'eventId',v_event.id);
end $$;

create or replace function reservations_private.resolve_event_scope(
 p_device_id uuid,p_event_id uuid,p_permission text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_event reservations.events%rowtype;v_context jsonb;
begin
 select * into v_event from reservations.events where id=p_event_id;
 if not found then raise exception 'RESERVATIONS_EVENT_NOT_FOUND' using errcode='P0002';end if;
 if p_permission='reservations.reports.view' then
  v_context:=public.require_effective_module_permission(p_device_id,'reservations',p_permission,null,null);
 else
  v_context:=public.require_effective_module_permission(p_device_id,'reservations',p_permission,'event',p_event_id::text);
 end if;
 if v_event.scope_type='conference' then
  if not exists(select 1 from public.conferences c where c.id=v_event.conference_id and c.deleted_at is null) then
   raise exception 'RESERVATIONS_CONFERENCE_ACCESS_REQUIRED' using errcode='42501';
  end if;
 elsif v_event.scope_type<>'standalone' then raise exception 'RESERVATIONS_SCOPE_TYPE_INVALID' using errcode='22023';end if;
 return v_context||jsonb_build_object('scopeType',v_event.scope_type,'scopePartitionId',v_event.scope_partition_id,'eventId',v_event.id,'conferenceId',v_event.conference_id);
end $$;

create or replace function reservations_private.allocate_booking_number(
 p_scope_partition_id uuid,p_year integer
) returns text language plpgsql security definer set search_path='' as $$
declare v_number bigint;
begin
 if p_scope_partition_id is null then raise exception 'RESERVATIONS_SCOPE_PARTITION_REQUIRED' using errcode='22023';end if;
 insert into reservations.booking_number_counters(scope_partition_id,booking_year,next_value)
 values(p_scope_partition_id,p_year,2)
 on conflict(scope_partition_id,booking_year) do update
 set next_value=reservations.booking_number_counters.next_value+1,updated_at=statement_timestamp()
 returning next_value-1 into v_number;
 return 'RES-'||lpad(p_year::text,4,'0')||'-'||lpad(v_number::text,4,'0');
end $$;

create or replace function reservations_private.read_scoped(p_device_id uuid,p_operation text,p_args jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 v_permission text; v_context jsonb; v_event_id uuid; v_booking_id uuid; v_conference_id uuid;
 v_partition uuid; v_limit integer:=coalesce((p_args->>'p_limit')::integer,100);
 v_result jsonb; v_after_created_at timestamptz; v_after_booking_id uuid; v_rows jsonb;
 v_has_more boolean; v_last_created_at timestamptz; v_last_booking_id uuid;
 v_link reservations.conference_person_links%rowtype; v_snapshot jsonb; v_room jsonb; v_house jsonb; v_floor jsonb;
begin
 if p_args is null or jsonb_typeof(p_args)<>'object' then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
 if p_args ?| array['scope_partition_id','p_scope_partition_id','device_id','p_device_id','actor_user_id','p_actor_user_id','actor_device_id','p_actor_device_id'] then raise exception 'RESERVATIONS_SCOPE_OVERRIDE_DENIED' using errcode='42501'; end if;
 v_permission:=case when p_operation in('list_conference_options','list_events','get_event','list_event_periods','list_booking_types') then 'reservations.event.view' when p_operation in('list_bookings','get_booking_detail','search_participants_bookings','get_booking_accommodation') then 'reservations.booking.view' when p_operation='list_booking_payments' then 'reservations.payment.view' when p_operation='list_attendance' then 'reservations.attendance.view' when p_operation='get_operational_state' then 'reservations.operations.view' when p_operation in('get_dashboard_summary','get_report_source_data','get_report_booking_page') then 'reservations.reports.view' end;
 if v_permission is null then raise exception 'RESERVATIONS_OPERATION_NOT_ALLOWED' using errcode='42501'; end if;

 if p_operation='list_conference_options' then
  perform platform_private.require_exact_jsonb_keys(p_args,array[]::text[]); v_context:=public.require_effective_module_permission(p_device_id,'reservations',v_permission,null,null);
  return coalesce(public.list_accessible_conferences(p_device_id)->'conferences','[]'::jsonb);
 end if;
 if p_operation='list_events' then
  if p_args ? 'p_conference_id' and not p_args ? 'p_scope_type' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_status','p_limit']); v_conference_id:=nullif(p_args->>'p_conference_id','')::uuid; if v_conference_id is null then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if; v_context:=reservations_private.conference_context(p_device_id,v_conference_id,v_permission);
  elsif p_args ? 'p_scope_type' and not p_args ? 'p_conference_id' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_scope_type','p_status','p_limit']); if p_args->>'p_scope_type'<>'standalone' then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if; v_context:=public.require_effective_module_permission(p_device_id,'reservations',v_permission,null,null);
  else raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
  if v_limit<1 or v_limit>5000 then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.start_date desc,x.id),'[]'::jsonb) into v_result from (select e.* from reservations.events e where ((v_conference_id is not null and e.scope_type='conference' and e.conference_id=v_conference_id) or (v_conference_id is null and e.scope_type='standalone' and e.conference_id is null)) and ((p_args->>'p_status') is null or e.status=p_args->>'p_status') order by e.start_date desc,e.id limit v_limit) x; return v_result;
 end if;

 if p_operation in('list_bookings','search_participants_bookings','list_attendance','get_report_source_data') and p_args ? 'p_conference_id' and p_args ? 'p_event_id' and p_args->'p_event_id'='null'::jsonb then
  v_conference_id:=nullif(p_args->>'p_conference_id','')::uuid; if v_conference_id is null then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if; v_context:=reservations_private.conference_context(p_device_id,v_conference_id,v_permission);
 elsif p_operation in('get_event','list_event_periods','list_booking_types','list_bookings','search_participants_bookings','list_attendance','get_report_source_data','get_report_booking_page') or (p_operation='get_dashboard_summary' and p_args ? 'p_event_id') then
  v_event_id:=nullif(p_args->>'p_event_id','')::uuid; if v_event_id is null then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if; v_context:=reservations_private.resolve_event_scope(p_device_id,v_event_id,v_permission);
 elsif p_operation in('get_booking_detail','list_booking_payments','get_operational_state','get_booking_accommodation') then
  v_booking_id:=nullif(p_args->>'p_booking_id','')::uuid; if v_booking_id is null then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if; v_context:=reservations_private.resolve_booking_scope(p_device_id,v_booking_id,v_permission);
 elsif p_operation='get_dashboard_summary' then
  v_conference_id:=nullif(p_args->>'p_conference_id','')::uuid; if v_conference_id is null then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if; v_context:=reservations_private.conference_context(p_device_id,v_conference_id,v_permission);
 end if;
 v_partition:=nullif(v_context->>'scopePartitionId','')::uuid;

 if p_operation='get_event' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_event_id']); select to_jsonb(e)||jsonb_build_object('periods',(select coalesce(jsonb_agg(to_jsonb(p) order by p.display_order),'[]') from reservations.event_periods p where p.event_id=e.id and p.scope_partition_id=e.scope_partition_id),'bookingTypes',(select coalesce(jsonb_agg(to_jsonb(t) order by t.display_order),'[]') from reservations.booking_types t where t.event_id=e.id and t.scope_partition_id=e.scope_partition_id)) into v_result from reservations.events e where e.id=v_event_id and e.scope_partition_id=v_partition;
 elsif p_operation='list_event_periods' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_event_id']); select coalesce(jsonb_agg(to_jsonb(p) order by p.display_order),'[]') into v_result from reservations.event_periods p where p.event_id=v_event_id and p.scope_partition_id=v_partition;
 elsif p_operation='list_booking_types' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_event_id']); select coalesce(jsonb_agg(to_jsonb(t) order by t.display_order),'[]') into v_result from reservations.booking_types t where t.event_id=v_event_id and t.scope_partition_id=v_partition;
 elsif p_operation in('list_bookings','search_participants_bookings') then
  perform platform_private.require_exact_jsonb_keys(p_args,case when p_operation='list_bookings' and v_conference_id is not null then array['p_conference_id','p_event_id','p_limit'] when p_operation='list_bookings' then array['p_event_id','p_limit'] when v_conference_id is not null then array['p_conference_id','p_query','p_event_id','p_limit'] else array['p_event_id','p_query','p_limit'] end); if v_limit<1 or v_limit>5000 then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id),'[]') into v_result from (select b.*,to_jsonb(p) participant,to_jsonb(e) event,coalesce(pay.total_paid,0) total_paid,greatest(b.price_snapshot-coalesce(pay.total_paid,0),0) remaining_balance,greatest(coalesce(pay.total_paid,0)-b.price_snapshot,0) overpaid_amount,case when coalesce(pay.total_paid,0)=0 then 'unpaid' when pay.total_paid>=b.price_snapshot then 'paid' else 'partial' end payment_status from reservations.bookings b join reservations.participants p on p.id=b.participant_id and p.scope_partition_id=b.scope_partition_id join reservations.events e on e.id=b.event_id and e.scope_partition_id=b.scope_partition_id left join lateral(select sum(z.amount) total_paid from reservations.payments z where z.booking_id=b.id and z.scope_partition_id=b.scope_partition_id and z.status='active') pay on true where ((v_event_id is not null and b.event_id=v_event_id and b.scope_partition_id=v_partition) or (v_event_id is null and e.scope_type='conference' and e.conference_id=v_conference_id)) and (p_operation='list_bookings' or lower(p.full_name||' '||p.phone||' '||b.booking_number) like '%'||lower(btrim(p_args->>'p_query'))||'%') order by b.created_at desc,b.id limit v_limit) x;
 elsif p_operation='get_booking_detail' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_booking_id']); select to_jsonb(b)||jsonb_build_object('participant',to_jsonb(p),'event',to_jsonb(e),'payments',(select coalesce(jsonb_agg(to_jsonb(z) order by z.payment_date desc,z.id),'[]') from reservations.payments z where z.booking_id=b.id and z.scope_partition_id=b.scope_partition_id),'attendance',(select coalesce(jsonb_agg(to_jsonb(a) order by a.segment),'[]') from reservations.attendance_records a where a.booking_id=b.id and a.scope_partition_id=b.scope_partition_id),'operationalReview',(select to_jsonb(o) from reservations.operational_reviews o where o.booking_id=b.id and o.scope_partition_id=b.scope_partition_id)) into v_result from reservations.bookings b join reservations.participants p on p.id=b.participant_id and p.scope_partition_id=b.scope_partition_id join reservations.events e on e.id=b.event_id and e.scope_partition_id=b.scope_partition_id where b.id=v_booking_id and b.scope_partition_id=v_partition;
 elsif p_operation='list_booking_payments' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_booking_id']); select coalesce(jsonb_agg(to_jsonb(z) order by z.payment_date desc,z.id),'[]') into v_result from reservations.payments z where z.booking_id=v_booking_id and z.scope_partition_id=v_partition;
 elsif p_operation='list_attendance' then
  perform platform_private.require_exact_jsonb_keys(p_args,case when v_conference_id is not null then array['p_conference_id','p_event_id','p_limit'] else array['p_event_id','p_limit'] end); if v_limit<1 or v_limit>5000 then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if; select coalesce(jsonb_agg(to_jsonb(x) order by x.full_name,x.booking_id,x.segment),'[]') into v_result from (select a.*,p.full_name,b.booking_number from reservations.attendance_records a join reservations.bookings b on b.id=a.booking_id and b.scope_partition_id=a.scope_partition_id join reservations.participants p on p.id=b.participant_id and p.scope_partition_id=b.scope_partition_id join reservations.events e on e.id=b.event_id and e.scope_partition_id=b.scope_partition_id where (v_event_id is not null and b.event_id=v_event_id and b.scope_partition_id=v_partition) or (v_event_id is null and e.scope_type='conference' and e.conference_id=v_conference_id) limit v_limit) x;
 elsif p_operation='get_operational_state' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_booking_id']); select to_jsonb(o)||jsonb_build_object('booking',to_jsonb(b),'participant',to_jsonb(p),'totalPaid',coalesce((select sum(z.amount) from reservations.payments z where z.booking_id=b.id and z.scope_partition_id=b.scope_partition_id and z.status='active'),0)) into v_result from reservations.operational_reviews o join reservations.bookings b on b.id=o.booking_id and b.scope_partition_id=o.scope_partition_id join reservations.participants p on p.id=b.participant_id and p.scope_partition_id=b.scope_partition_id where o.booking_id=v_booking_id and o.scope_partition_id=v_partition;
 elsif p_operation='get_booking_accommodation' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_booking_id']); if v_context->>'scopeType'='standalone' then return reservations_private.standalone_accommodation_not_applicable(v_booking_id); end if; select l.* into v_link from reservations.conference_person_links l where l.booking_id=v_booking_id; if not found then return jsonb_build_object('bookingId',v_booking_id,'linked',false,'readyForAccommodation',false,'accommodated',false); end if; select s.data into v_snapshot from public.conference_snapshots s where s.conference_id=v_link.conference_id; select h.value,f.value,r.value into v_house,v_floor,v_room from jsonb_array_elements(case when jsonb_typeof(v_snapshot->'houses')='array' then v_snapshot->'houses' else '[]'::jsonb end) h(value) cross join lateral jsonb_array_elements(case when jsonb_typeof(h.value->'floors')='array' then h.value->'floors' else '[]'::jsonb end) f(value) cross join lateral jsonb_array_elements(case when jsonb_typeof(f.value->'rooms')='array' then f.value->'rooms' else '[]'::jsonb end) r(value) where exists(select 1 from jsonb_array_elements((case when jsonb_typeof(r.value->'guests')='array' then r.value->'guests' else '[]'::jsonb end)||(case when jsonb_typeof(r.value->'children')='array' then r.value->'children' else '[]'::jsonb end)) occupant where occupant->>'personId'=v_link.conference_person_id::text) limit 1; return jsonb_strip_nulls(jsonb_build_object('bookingId',v_booking_id,'conferenceId',v_link.conference_id,'conferencePersonId',v_link.conference_person_id,'linked',true,'readyForAccommodation',true,'accommodated',v_room is not null,'roomId',v_room->>'id','roomNumber',v_room->>'number','houseLabel',v_house->>'name','floorLabel',v_floor->>'name'));
 elsif p_operation='get_dashboard_summary' then
  perform platform_private.require_exact_jsonb_keys(p_args,case when p_args ? 'p_event_id' and not p_args ? 'p_conference_id' then array['p_event_id'] when p_args ? 'p_conference_id' and not p_args ? 'p_event_id' then array['p_conference_id'] else array['__invalid__'] end); return jsonb_build_object('events',(select count(*) from reservations.events e where (v_event_id is not null and e.id=v_event_id and e.scope_partition_id=v_partition) or (v_event_id is null and e.scope_type='conference' and e.conference_id=v_conference_id)),'bookings',(select count(*) from reservations.bookings b join reservations.events e on e.id=b.event_id and e.scope_partition_id=b.scope_partition_id where (v_event_id is not null and e.id=v_event_id and e.scope_partition_id=v_partition) or (v_event_id is null and e.scope_type='conference' and e.conference_id=v_conference_id)),'bookingValue',(select coalesce(sum(b.price_snapshot),0) from reservations.bookings b join reservations.events e on e.id=b.event_id and e.scope_partition_id=b.scope_partition_id where (v_event_id is not null and e.id=v_event_id and e.scope_partition_id=v_partition) or (v_event_id is null and e.scope_type='conference' and e.conference_id=v_conference_id)),'collected',(select coalesce(sum(z.amount),0) from reservations.payments z join reservations.bookings b on b.id=z.booking_id and b.scope_partition_id=z.scope_partition_id join reservations.events e on e.id=b.event_id and e.scope_partition_id=b.scope_partition_id where z.status='active' and ((v_event_id is not null and e.id=v_event_id and e.scope_partition_id=v_partition) or (v_event_id is null and e.scope_type='conference' and e.conference_id=v_conference_id))));
 elsif p_operation='get_report_source_data' then
  perform platform_private.require_exact_jsonb_keys(p_args,case when v_conference_id is not null then array['p_conference_id','p_event_id','p_limit'] else array['p_event_id','p_limit'] end); if v_limit<1 or v_limit>5000 then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if; return jsonb_build_object('events',(select coalesce(jsonb_agg(to_jsonb(x) order by x.start_date,x.id),'[]') from (select e.* from reservations.events e where (v_event_id is not null and e.id=v_event_id and e.scope_partition_id=v_partition) or (v_event_id is null and e.scope_type='conference' and e.conference_id=v_conference_id) order by e.start_date,e.id limit v_limit) x),'periods',(select coalesce(jsonb_agg(to_jsonb(x) order by x.display_order,x.id),'[]') from (select p.* from reservations.event_periods p join reservations.events e on e.id=p.event_id and e.scope_partition_id=p.scope_partition_id where (v_event_id is not null and e.id=v_event_id and e.scope_partition_id=v_partition) or (v_event_id is null and e.scope_type='conference' and e.conference_id=v_conference_id) order by p.display_order,p.id limit v_limit) x),'bookingTypes',(select coalesce(jsonb_agg(to_jsonb(x) order by x.display_order,x.id),'[]') from (select t.* from reservations.booking_types t join reservations.events e on e.id=t.event_id and e.scope_partition_id=t.scope_partition_id where (v_event_id is not null and e.id=v_event_id and e.scope_partition_id=v_partition) or (v_event_id is null and e.scope_type='conference' and e.conference_id=v_conference_id) order by t.display_order,t.id limit v_limit) x),'participants',(select coalesce(jsonb_agg(to_jsonb(x) order by x.full_name,x.id),'[]') from (select distinct p.* from reservations.participants p join reservations.bookings b on b.participant_id=p.id and b.scope_partition_id=p.scope_partition_id join reservations.events e on e.id=b.event_id and e.scope_partition_id=b.scope_partition_id where (v_event_id is not null and e.id=v_event_id and e.scope_partition_id=v_partition) or (v_event_id is null and e.scope_type='conference' and e.conference_id=v_conference_id) order by p.full_name,p.id limit v_limit) x),'bookings',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at,x.id),'[]') from (select b.* from reservations.bookings b join reservations.events e on e.id=b.event_id and e.scope_partition_id=b.scope_partition_id where (v_event_id is not null and e.id=v_event_id and e.scope_partition_id=v_partition) or (v_event_id is null and e.scope_type='conference' and e.conference_id=v_conference_id) order by b.created_at,b.id limit v_limit) x),'payments',(select coalesce(jsonb_agg(to_jsonb(x) order by x.payment_date,x.id),'[]') from (select z.* from reservations.payments z join reservations.bookings b on b.id=z.booking_id and b.scope_partition_id=z.scope_partition_id join reservations.events e on e.id=b.event_id and e.scope_partition_id=b.scope_partition_id where (v_event_id is not null and e.id=v_event_id and e.scope_partition_id=v_partition) or (v_event_id is null and e.scope_type='conference' and e.conference_id=v_conference_id) order by z.payment_date,z.id limit v_limit) x),'attendance',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at,x.id),'[]') from (select a.* from reservations.attendance_records a join reservations.bookings b on b.id=a.booking_id and b.scope_partition_id=a.scope_partition_id join reservations.events e on e.id=b.event_id and e.scope_partition_id=b.scope_partition_id where (v_event_id is not null and e.id=v_event_id and e.scope_partition_id=v_partition) or (v_event_id is null and e.scope_type='conference' and e.conference_id=v_conference_id) order by a.created_at,a.id limit v_limit) x),'operationalReviews',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at,x.id),'[]') from (select o.* from reservations.operational_reviews o join reservations.bookings b on b.id=o.booking_id and b.scope_partition_id=o.scope_partition_id join reservations.events e on e.id=b.event_id and e.scope_partition_id=b.scope_partition_id where (v_event_id is not null and e.id=v_event_id and e.scope_partition_id=v_partition) or (v_event_id is null and e.scope_type='conference' and e.conference_id=v_conference_id) order by o.created_at,o.id limit v_limit) x));
 elsif p_operation='get_report_booking_page' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_event_id','p_limit','p_after_created_at','p_after_booking_id']); v_after_created_at:=nullif(p_args->>'p_after_created_at','')::timestamptz; v_after_booking_id:=nullif(p_args->>'p_after_booking_id','')::uuid; if not (p_args ? 'p_limit') or v_limit<1 or v_limit>500 or ((v_after_created_at is null)<>(v_after_booking_id is null)) then raise exception 'RESERVATIONS_REPORT_PAGE_ARGUMENTS_INVALID' using errcode='22023'; end if;
  with candidates as materialized(select b.* from reservations.bookings b where b.event_id=v_event_id and b.scope_partition_id=v_partition and (v_after_created_at is null or b.created_at>v_after_created_at or (b.created_at=v_after_created_at and b.id>v_after_booking_id)) order by b.created_at,b.id limit v_limit+1),page as materialized(select * from candidates order by created_at,id limit v_limit) select coalesce(jsonb_agg(jsonb_build_object('booking',to_jsonb(b),'participant',to_jsonb(p),'payments',coalesce((select jsonb_agg(to_jsonb(z) order by z.payment_date,z.id) from reservations.payments z where z.booking_id=b.id and z.scope_partition_id=b.scope_partition_id),'[]'),'attendance',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at,a.id) from reservations.attendance_records a where a.booking_id=b.id and a.scope_partition_id=b.scope_partition_id),'[]'),'operationalReview',(select to_jsonb(o) from reservations.operational_reviews o where o.booking_id=b.id and o.scope_partition_id=b.scope_partition_id)) order by b.created_at,b.id),'[]'),(select count(*)>v_limit from candidates),(array_agg(b.created_at order by b.created_at desc,b.id desc))[1],(array_agg(b.id order by b.created_at desc,b.id desc))[1] into v_rows,v_has_more,v_last_created_at,v_last_booking_id from page b join reservations.participants p on p.id=b.participant_id and p.scope_partition_id=b.scope_partition_id; return jsonb_build_object('rows',v_rows,'hasMore',coalesce(v_has_more,false),'nextCursor',case when coalesce(v_has_more,false) then jsonb_build_object('createdAt',v_last_created_at,'bookingId',v_last_booking_id) else null end);
 end if;
 if v_result is null then raise exception 'RESERVATIONS_RECORD_NOT_FOUND' using errcode='P0002'; end if; return v_result;
end $$;

create or replace function reservations_private.mutate_scoped(p_device_id uuid,p_operation text,p_args jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_context jsonb; v_replay jsonb; v_result jsonb; v_event reservations.events%rowtype; v_period reservations.event_periods%rowtype; v_type reservations.booking_types%rowtype; v_booking reservations.bookings%rowtype; v_payment reservations.payments%rowtype; v_operation reservations.operations%rowtype; v_id uuid; v_revision bigint; v_actor uuid; v_partition uuid; v_number text; v_operation_id uuid:=(p_args->>'p_operation_id')::uuid; v_count integer;
begin
 if p_args is null or jsonb_typeof(p_args)<>'object' or p_args ?| array['scope_partition_id','p_scope_partition_id','device_id','p_device_id','actor_user_id','p_actor_user_id','actor_device_id','p_actor_device_id'] then raise exception 'RESERVATIONS_SCOPE_OVERRIDE_DENIED' using errcode='42501'; end if;
 if p_operation='delete_event' and v_operation_id is not null then
  select * into v_operation from reservations.operations where operation_id=v_operation_id;
  if found then
   v_context:=public.require_effective_module_permission(p_device_id,'reservations','reservations.event.manage',null,null)||jsonb_build_object('scopePartitionId',v_operation.scope_partition_id);
   return reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args);
  end if;
 end if;
 if p_operation='delete_event_period' and v_operation_id is not null then
  select * into v_operation from reservations.operations where operation_id=v_operation_id;
  if found then
   v_context:=public.require_effective_module_permission(p_device_id,'reservations','reservations.event.manage',null,null)||jsonb_build_object('scopePartitionId',v_operation.scope_partition_id);
   return reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args);
  end if;
 end if;
 if p_operation='delete_booking' and v_operation_id is not null then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_expected_revision']);
  select * into v_operation from reservations.operations where operation_id=v_operation_id;
  if found then
   v_context:=public.require_effective_module_permission(p_device_id,'reservations','reservations.booking.delete',null,null)||jsonb_build_object('scopePartitionId',v_operation.scope_partition_id);
   return reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args);
  end if;
 end if;
 if p_operation='create_event' then
  if p_args->>'p_scope_type'='standalone' then
   return reservations_private.create_standalone_event_scoped(p_device_id,p_args-'p_scope_type');
  elsif p_args->>'p_scope_type'<>'conference' or (p_args->>'p_conference_id')::uuid is null then raise exception 'RESERVATIONS_CREATE_EVENT_SCOPE_INVALID' using errcode='22023'; end if;
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_scope_type','p_conference_id','p_name','p_start_date','p_end_date','p_location','p_capacity','p_status','p_notes']);
  v_context:=reservations_private.conference_context(p_device_id,(p_args->>'p_conference_id')::uuid,'reservations.event.manage'); v_actor:=(v_context->>'actorUserId')::uuid; v_partition:=(v_context->>'scopePartitionId')::uuid;
  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,'create_event',p_args); if v_replay is not null then return v_replay; end if;
  insert into reservations.events(scope_type,scope_partition_id,conference_id,name,start_date,end_date,location,capacity,status,notes,created_by,updated_by) values('conference',v_partition,(p_args->>'p_conference_id')::uuid,btrim(p_args->>'p_name'),(p_args->>'p_start_date')::date,(p_args->>'p_end_date')::date,coalesce(p_args->>'p_location',''),(p_args->>'p_capacity')::integer,p_args->>'p_status',coalesce(p_args->>'p_notes',''),v_actor,v_actor) returning id,revision into v_id,v_revision;
  v_result:=jsonb_build_object('eventId',v_id,'revision',v_revision,'scopeType','conference','scopePartitionId',v_partition); perform reservations_private.audit(v_context||jsonb_build_object('scopeType','conference','scopePartitionId',v_partition),'event.created','event',v_id,v_operation_id,null,v_result); return reservations_private.complete_operation(v_operation_id,v_context,'create_event',p_args,v_result);
 end if;
 if p_operation='update_event' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_expected_revision','p_name','p_start_date','p_end_date','p_location','p_capacity','p_status','p_notes']); v_context:=reservations_private.resolve_event_scope(p_device_id,(p_args->>'p_event_id')::uuid,'reservations.event.manage');
  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_event from reservations.events where id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for update; if v_event.revision<>(p_args->>'p_expected_revision')::bigint then raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001'; end if;
  update reservations.events set name=btrim(p_args->>'p_name'),start_date=(p_args->>'p_start_date')::date,end_date=(p_args->>'p_end_date')::date,location=coalesce(p_args->>'p_location',''),capacity=(p_args->>'p_capacity')::integer,status=p_args->>'p_status',notes=coalesce(p_args->>'p_notes',''),revision=revision+1,updated_at=statement_timestamp(),updated_by=(v_context->>'actorUserId')::uuid where id=v_event.id returning revision into v_revision; if exists(select 1 from reservations.event_periods where event_id=v_event.id and (starts_on<(p_args->>'p_start_date')::date or ends_on>(p_args->>'p_end_date')::date)) then raise exception 'RESERVATIONS_EVENT_PERIOD_OUT_OF_RANGE' using errcode='22023'; end if; v_result:=jsonb_build_object('eventId',v_event.id,'revision',v_revision); perform reservations_private.audit(v_context,'event.updated','event',v_event.id,v_operation_id,to_jsonb(v_event),v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='delete_event' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_expected_revision']); v_context:=reservations_private.resolve_event_scope(p_device_id,(p_args->>'p_event_id')::uuid,'reservations.event.manage'); v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_event from reservations.events where id=(v_context->>'eventId')::uuid for update; if v_event.revision<>(p_args->>'p_expected_revision')::bigint then raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001'; end if; if exists(select 1 from reservations.bookings where event_id=v_event.id and scope_partition_id=v_event.scope_partition_id) then raise exception 'RESERVATIONS_EVENT_HAS_DEPENDENCIES' using errcode='55000'; end if; delete from reservations.event_periods where event_id=v_event.id and scope_partition_id=v_event.scope_partition_id; delete from reservations.booking_types where event_id=v_event.id and scope_partition_id=v_event.scope_partition_id; delete from reservations.events where id=v_event.id; v_result:=jsonb_build_object('eventId',v_event.id,'deleted',true); perform reservations_private.audit(v_context,'event.deleted','event',v_event.id,v_operation_id,to_jsonb(v_event),null); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='create_event_period' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_kind','p_starts_on','p_ends_on','p_display_order']); v_context:=reservations_private.resolve_event_scope(p_device_id,(p_args->>'p_event_id')::uuid,'reservations.event.manage'); v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_event from reservations.events where id=(v_context->>'eventId')::uuid for key share; if p_args->>'p_kind' not in ('conference','caravans') or (p_args->>'p_starts_on')::date<v_event.start_date or (p_args->>'p_ends_on')::date>v_event.end_date then raise exception 'RESERVATIONS_EVENT_PERIOD_OUT_OF_RANGE' using errcode='22023'; end if; insert into reservations.event_periods(scope_partition_id,event_id,kind,starts_on,ends_on,display_order,created_by,updated_by) values(v_event.scope_partition_id,v_event.id,p_args->>'p_kind',(p_args->>'p_starts_on')::date,(p_args->>'p_ends_on')::date,(p_args->>'p_display_order')::integer,(v_context->>'actorUserId')::uuid,(v_context->>'actorUserId')::uuid) returning id,revision into v_id,v_revision; v_result:=jsonb_build_object('periodId',v_id,'revision',v_revision); perform reservations_private.audit(v_context,'event_period.created','event_period',v_id,v_operation_id,null,v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation in ('update_event_period','delete_event_period') then
  perform platform_private.require_exact_jsonb_keys(p_args,case when p_operation='update_event_period' then array['p_operation_id','p_period_id','p_expected_revision','p_kind','p_starts_on','p_ends_on','p_display_order'] else array['p_operation_id','p_period_id','p_expected_revision'] end); v_context:=reservations_private.resolve_event_period_scope(p_device_id,(p_args->>'p_period_id')::uuid,'reservations.event.manage'); v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_period from reservations.event_periods where id=(v_context->>'periodId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for update; if v_period.revision<>(p_args->>'p_expected_revision')::bigint then raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001'; end if; if p_operation='delete_event_period' then delete from reservations.event_periods where id=v_period.id; v_result:=jsonb_build_object('periodId',v_period.id,'deleted',true); else select * into v_event from reservations.events where id=v_period.event_id; if p_args->>'p_kind' not in ('conference','caravans') or (p_args->>'p_starts_on')::date<v_event.start_date or (p_args->>'p_ends_on')::date>v_event.end_date then raise exception 'RESERVATIONS_EVENT_PERIOD_OUT_OF_RANGE' using errcode='22023'; end if; update reservations.event_periods set kind=p_args->>'p_kind',starts_on=(p_args->>'p_starts_on')::date,ends_on=(p_args->>'p_ends_on')::date,display_order=(p_args->>'p_display_order')::integer,revision=revision+1,updated_at=statement_timestamp(),updated_by=(v_context->>'actorUserId')::uuid where id=v_period.id returning revision into v_revision; v_result:=jsonb_build_object('periodId',v_period.id,'revision',v_revision); end if; perform reservations_private.audit(v_context,'event_period.'||case when p_operation='delete_event_period' then 'deleted' else 'updated' end,'event_period',v_period.id,v_operation_id,to_jsonb(v_period),v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='create_booking_type' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_name','p_code','p_price','p_active','p_display_order','p_eligible_attendance_segments']); v_context:=reservations_private.resolve_event_scope(p_device_id,(p_args->>'p_event_id')::uuid,'reservations.event.manage'); v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_event from reservations.events where id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for key share; insert into reservations.booking_types(scope_partition_id,event_id,name,code,price,active,display_order,eligible_attendance_segments,created_by,updated_by) values(v_event.scope_partition_id,v_event.id,btrim(p_args->>'p_name'),btrim(p_args->>'p_code'),(p_args->>'p_price')::numeric,(p_args->>'p_active')::boolean,(p_args->>'p_display_order')::integer,coalesce((select array_agg(value) from jsonb_array_elements_text(p_args->'p_eligible_attendance_segments') s(value)),'{}'::text[]),(v_context->>'actorUserId')::uuid,(v_context->>'actorUserId')::uuid) returning id,revision into v_id,v_revision; v_result:=jsonb_build_object('bookingTypeId',v_id,'revision',v_revision); perform reservations_private.audit(v_context,'booking_type.created','booking_type',v_id,v_operation_id,null,v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='update_booking_type' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_type_id','p_expected_revision','p_name','p_code','p_price','p_active','p_display_order','p_eligible_attendance_segments']); v_context:=reservations_private.resolve_booking_type_scope(p_device_id,(p_args->>'p_booking_type_id')::uuid,'reservations.event.manage'); v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_type from reservations.booking_types where id=(v_context->>'bookingTypeId')::uuid and event_id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for update; if not found then raise exception 'RESERVATIONS_BOOKING_TYPE_NOT_FOUND' using errcode='P0002'; end if; if v_type.revision<>(p_args->>'p_expected_revision')::bigint then raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001'; end if;
  update reservations.booking_types set name=btrim(p_args->>'p_name'),code=btrim(p_args->>'p_code'),price=(p_args->>'p_price')::numeric,active=(p_args->>'p_active')::boolean,display_order=(p_args->>'p_display_order')::integer,eligible_attendance_segments=coalesce((select array_agg(value) from jsonb_array_elements_text(p_args->'p_eligible_attendance_segments') s(value)),'{}'::text[]),revision=revision+1,updated_at=statement_timestamp(),updated_by=(v_context->>'actorUserId')::uuid where id=v_type.id and event_id=v_type.event_id and scope_partition_id=v_type.scope_partition_id returning revision into v_revision; v_result:=jsonb_build_object('bookingTypeId',v_type.id,'revision',v_revision); perform reservations_private.audit(v_context,'booking_type.updated','booking_type',v_type.id,v_operation_id,to_jsonb(v_type),v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='create_booking' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_booking_type_id','p_full_name','p_phone','p_age','p_church','p_governorate','p_city_or_village','p_service_sector','p_service_sector_other','p_notes']); v_context:=reservations_private.resolve_event_scope(p_device_id,(p_args->>'p_event_id')::uuid,'reservations.booking.create'); v_actor:=(v_context->>'actorUserId')::uuid;
  select * into v_event from reservations.events where id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for update; if not found or v_event.status in('closed','full') then raise exception 'RESERVATIONS_EVENT_NOT_ACCEPTING_BOOKINGS' using errcode='22023'; end if; select * into v_type from reservations.booking_types where id=(p_args->>'p_booking_type_id')::uuid and event_id=v_event.id and scope_partition_id=v_event.scope_partition_id for key share; if not found or not v_type.active then raise exception 'RESERVATIONS_BOOKING_TYPE_INACTIVE' using errcode='22023'; end if; select count(*) into v_count from reservations.bookings where event_id=v_event.id and scope_partition_id=v_event.scope_partition_id; if v_event.capacity is not null and v_count>=v_event.capacity then raise exception 'RESERVATIONS_EVENT_CAPACITY_REACHED' using errcode='22023'; end if;
  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; v_number:=reservations_private.allocate_booking_number(v_event.scope_partition_id,extract(year from v_event.start_date)::integer); perform set_config('reservations.scope_partition_id',v_event.scope_partition_id::text,true); insert into reservations.participants(scope_partition_id,full_name,phone,age,church,governorate,city_or_village,service_sector,service_sector_other,notes,created_by,updated_by) values(v_event.scope_partition_id,btrim(p_args->>'p_full_name'),btrim(p_args->>'p_phone'),(p_args->>'p_age')::integer,coalesce(p_args->>'p_church',''),btrim(p_args->>'p_governorate'),coalesce(p_args->>'p_city_or_village',''),p_args->>'p_service_sector',nullif(btrim(p_args->>'p_service_sector_other'),''),nullif(p_args->>'p_notes',''),v_actor,v_actor) returning id into v_id; insert into reservations.bookings(scope_partition_id,booking_number,participant_id,event_id,booking_type_id,booking_type_name_snapshot,price_snapshot,attendance_segments_snapshot,notes,created_by,updated_by) values(v_event.scope_partition_id,v_number,v_id,v_event.id,v_type.id,v_type.name,v_type.price,v_type.eligible_attendance_segments,nullif(p_args->>'p_notes',''),v_actor,v_actor) returning id,revision into v_booking.id,v_revision; insert into reservations.operational_reviews(scope_partition_id,booking_id,created_by,updated_by) values(v_event.scope_partition_id,v_booking.id,v_actor,v_actor); v_result:=jsonb_build_object('participantId',v_id,'bookingId',v_booking.id,'bookingNumber',v_number,'revision',v_revision); perform reservations_private.audit(v_context,'booking.created','booking',v_booking.id,v_operation_id,null,v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='update_participant_booking' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_expected_revision','p_booking_type_id','p_full_name','p_phone','p_age','p_church','p_governorate','p_city_or_village','p_service_sector','p_service_sector_other','p_notes']); v_context:=reservations_private.resolve_booking_scope(p_device_id,(p_args->>'p_booking_id')::uuid,'reservations.booking.update'); v_actor:=(v_context->>'actorUserId')::uuid;
  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_booking from reservations.bookings where id=(v_context->>'bookingId')::uuid and event_id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for update; if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002'; end if; if v_booking.revision<>(p_args->>'p_expected_revision')::bigint then raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001'; end if;
  select * into v_type from reservations.booking_types where id=(p_args->>'p_booking_type_id')::uuid and event_id=v_booking.event_id and scope_partition_id=v_booking.scope_partition_id for key share; if not found then raise exception 'RESERVATIONS_BOOKING_TYPE_EVENT_MISMATCH' using errcode='22023'; end if; if v_type.id<>v_booking.booking_type_id and not v_type.active then raise exception 'RESERVATIONS_BOOKING_TYPE_INACTIVE' using errcode='22023'; end if;
  update reservations.participants set full_name=btrim(p_args->>'p_full_name'),phone=btrim(p_args->>'p_phone'),age=(p_args->>'p_age')::integer,church=coalesce(p_args->>'p_church',''),governorate=btrim(p_args->>'p_governorate'),city_or_village=coalesce(p_args->>'p_city_or_village',''),service_sector=p_args->>'p_service_sector',service_sector_other=nullif(btrim(p_args->>'p_service_sector_other'),''),notes=nullif(p_args->>'p_notes',''),revision=revision+1,updated_at=statement_timestamp(),updated_by=v_actor where id=v_booking.participant_id and scope_partition_id=v_booking.scope_partition_id; if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002'; end if; update reservations.bookings set booking_type_id=v_type.id,booking_type_name_snapshot=v_type.name,price_snapshot=v_type.price,notes=nullif(p_args->>'p_notes',''),revision=revision+1,updated_at=statement_timestamp(),updated_by=v_actor where id=v_booking.id and event_id=v_booking.event_id and scope_partition_id=v_booking.scope_partition_id returning revision into v_revision; v_result:=jsonb_build_object('bookingId',v_booking.id,'bookingTypeId',v_type.id,'revision',v_revision); perform reservations_private.audit(v_context,'booking.updated','booking',v_booking.id,v_operation_id,to_jsonb(v_booking),v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='delete_booking' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_expected_revision']); v_context:=reservations_private.resolve_booking_scope(p_device_id,(p_args->>'p_booking_id')::uuid,'reservations.booking.delete');
  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_booking from reservations.bookings where id=(v_context->>'bookingId')::uuid and event_id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for update; if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002'; end if; if v_booking.revision<>(p_args->>'p_expected_revision')::bigint then raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001'; end if;
  if exists(select 1 from reservations.conference_person_links where booking_id=v_booking.id) then raise exception 'RESERVATIONS_CONFERENCE_PERSON_MANUAL_ACTION_REQUIRED' using errcode='55000'; end if; if exists(select 1 from reservations.payments where booking_id=v_booking.id and scope_partition_id=v_booking.scope_partition_id) or exists(select 1 from reservations.attendance_records where booking_id=v_booking.id and scope_partition_id=v_booking.scope_partition_id) then raise exception 'RESERVATIONS_BOOKING_HAS_HISTORY' using errcode='55000'; end if;
  delete from reservations.bookings where id=v_booking.id and event_id=v_booking.event_id and scope_partition_id=v_booking.scope_partition_id; v_result:=jsonb_build_object('bookingId',v_booking.id,'deleted',true); perform reservations_private.audit(v_context,'booking.deleted','booking',v_booking.id,v_operation_id,to_jsonb(v_booking),null); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='record_payment' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_amount','p_payment_date','p_payment_method','p_payment_method_other','p_reference','p_notes']); v_context:=reservations_private.resolve_booking_scope(p_device_id,(p_args->>'p_booking_id')::uuid,'reservations.payment.record'); v_actor:=(v_context->>'actorUserId')::uuid;
  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_booking from reservations.bookings where id=(v_context->>'bookingId')::uuid and event_id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for key share; if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002'; end if;
  insert into reservations.payments(scope_partition_id,booking_id,amount,payment_date,payment_method,payment_method_other,reference,notes,created_by,created_by_device_id) values(v_booking.scope_partition_id,v_booking.id,(p_args->>'p_amount')::numeric,(p_args->>'p_payment_date')::date,p_args->>'p_payment_method',nullif(btrim(p_args->>'p_payment_method_other'),''),nullif(p_args->>'p_reference',''),nullif(p_args->>'p_notes',''),v_actor,p_device_id) returning id into v_id; v_result:=jsonb_build_object('paymentId',v_id,'status','active'); perform reservations_private.audit(v_context,'payment.recorded','payment',v_id,v_operation_id,null,v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='void_payment' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_payment_id','p_void_reason']); v_context:=reservations_private.resolve_payment_scope(p_device_id,(p_args->>'p_payment_id')::uuid,'reservations.payment.void'); v_actor:=(v_context->>'actorUserId')::uuid;
  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_payment from reservations.payments where id=(v_context->>'paymentId')::uuid and booking_id=(v_context->>'bookingId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for update; if not found then raise exception 'RESERVATIONS_PAYMENT_NOT_FOUND' using errcode='P0002'; end if; if v_payment.status<>'active' or nullif(btrim(p_args->>'p_void_reason'),'') is null then raise exception 'RESERVATIONS_PAYMENT_VOID_INVALID' using errcode='22023'; end if;
  update reservations.payments set status='voided',voided_at=statement_timestamp(),void_reason=btrim(p_args->>'p_void_reason'),voided_by=v_actor,voided_by_device_id=p_device_id where id=v_payment.id and booking_id=v_payment.booking_id and scope_partition_id=v_payment.scope_partition_id; v_result:=jsonb_build_object('paymentId',v_payment.id,'status','voided'); perform reservations_private.audit(v_context,'payment.voided','payment',v_payment.id,v_operation_id,to_jsonb(v_payment),v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='update_attendance' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_segment','p_attended','p_attendance_date','p_notes']); v_context:=reservations_private.resolve_booking_scope(p_device_id,(p_args->>'p_booking_id')::uuid,'reservations.attendance.manage'); v_actor:=(v_context->>'actorUserId')::uuid;
  select * into v_booking from reservations.bookings where id=(v_context->>'bookingId')::uuid and event_id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for key share; if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002'; end if; if cardinality(v_booking.attendance_segments_snapshot)=0 then raise exception 'RESERVATIONS_ATTENDANCE_NOT_APPLICABLE' using errcode='22023'; end if; if not (p_args->>'p_segment'=any(v_booking.attendance_segments_snapshot)) then raise exception 'RESERVATIONS_ATTENDANCE_SEGMENT_INELIGIBLE' using errcode='22023'; end if;
  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; insert into reservations.attendance_records(scope_partition_id,booking_id,segment,attended,attendance_date,notes,created_by,updated_by) values(v_booking.scope_partition_id,v_booking.id,p_args->>'p_segment',(p_args->>'p_attended')::boolean,case when (p_args->>'p_attended')::boolean then coalesce((p_args->>'p_attendance_date')::date,current_date) end,nullif(p_args->>'p_notes',''),v_actor,v_actor) on conflict(booking_id,segment) do update set attended=excluded.attended,attendance_date=excluded.attendance_date,notes=excluded.notes,revision=reservations.attendance_records.revision+1,updated_at=statement_timestamp(),updated_by=v_actor returning id,revision into v_id,v_revision; v_result:=jsonb_build_object('attendanceId',v_id,'revision',v_revision,'attended',(p_args->>'p_attended')::boolean); perform reservations_private.audit(v_context,'attendance.corrected','attendance',v_id,v_operation_id,null,v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='update_operational_review' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_expected_revision','p_review_status']); v_context:=reservations_private.resolve_booking_scope(p_device_id,(p_args->>'p_booking_id')::uuid,'reservations.operations.manage'); v_actor:=(v_context->>'actorUserId')::uuid;
  select o.id,o.revision into v_id,v_revision from reservations.operational_reviews o where o.booking_id=(v_context->>'bookingId')::uuid and o.scope_partition_id=(v_context->>'scopePartitionId')::uuid for update; if not found then raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001'; end if; v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if;
  update reservations.operational_reviews o set review_status=p_args->>'p_review_status',reviewed_at=case when p_args->>'p_review_status'='completed' then statement_timestamp() end,reviewed_by=case when p_args->>'p_review_status'='completed' then v_actor end,reviewed_by_device_id=case when p_args->>'p_review_status'='completed' then p_device_id end,revision=o.revision+1,updated_at=statement_timestamp(),updated_by=v_actor where o.id=v_id and o.booking_id=(v_context->>'bookingId')::uuid and o.scope_partition_id=(v_context->>'scopePartitionId')::uuid and o.revision=(p_args->>'p_expected_revision')::bigint returning o.id,o.revision into v_id,v_revision; if not found then raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001'; end if; v_result:=jsonb_build_object('operationalReviewId',v_id,'revision',v_revision,'status',p_args->>'p_review_status'); perform reservations_private.audit(v_context,'operational_review.updated','operational_review',v_id,v_operation_id,null,v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='reorder_event_periods' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_period_ids']); v_context:=reservations_private.resolve_event_scope(p_device_id,(p_args->>'p_event_id')::uuid,'reservations.event.manage'); v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; if jsonb_typeof(p_args->'p_period_ids')<>'array' or (select count(*) from jsonb_array_elements_text(p_args->'p_period_ids'))<>(select count(*) from reservations.event_periods where event_id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid) or (select count(distinct value) from jsonb_array_elements_text(p_args->'p_period_ids') s(value))<>(select count(*) from jsonb_array_elements_text(p_args->'p_period_ids')) or exists(select 1 from jsonb_array_elements_text(p_args->'p_period_ids') x left join reservations.event_periods p on p.id=x::uuid and p.event_id=(v_context->>'eventId')::uuid and p.scope_partition_id=(v_context->>'scopePartitionId')::uuid where p.id is null) then raise exception 'RESERVATIONS_PERIOD_ORDER_INVALID' using errcode='22023'; end if; update reservations.event_periods p set display_order=x.ordinality-1,revision=p.revision+1,updated_at=statement_timestamp(),updated_by=(v_context->>'actorUserId')::uuid from jsonb_array_elements_text(p_args->'p_period_ids') with ordinality x(id,ordinality) where p.id=x.id::uuid and p.event_id=(v_context->>'eventId')::uuid and p.scope_partition_id=(v_context->>'scopePartitionId')::uuid; v_result:=jsonb_build_object('eventId',(v_context->>'eventId')::uuid,'reordered',true); perform reservations_private.audit(v_context,'event_periods.reordered','event',(v_context->>'eventId')::uuid,v_operation_id,null,v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 raise exception 'RESERVATIONS_SCOPED_OPERATION_NOT_IMPLEMENTED' using errcode='0A000';
end $$;
-- Canonical Conference contracts are resource-scoped and Organization-free.
drop function if exists public.create_canonical_conference(uuid,uuid,uuid,uuid,text,date,date);
create or replace function public.get_conference_core(
  p_actor_device_id uuid,
  p_conference_id uuid
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_context jsonb;
  v_actor uuid;
  v_conference public.conferences%rowtype;
  v_schedule jsonb;
begin
  if p_conference_id is null then
    raise exception 'CONFERENCE_CORE_ARGUMENT_INVALID' using errcode='22023';
  end if;
  v_context:=public.require_effective_module_permission(
    p_actor_device_id,'conference','conference.access.view',
    'conference',p_conference_id::text
  );
  v_actor:=(v_context->>'actorUserId')::uuid;
  if platform_private.validated_phase1c_device_authorization(
    v_actor,p_actor_device_id
  ) is null then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end if;
  select conferences.* into v_conference
  from public.conferences conferences
  where conferences.id=p_conference_id and conferences.deleted_at is null;
  if not found then
    raise exception 'CONFERENCE_CORE_NOT_FOUND' using errcode='P0002';
  end if;
  select coalesce(
    jsonb_agg(to_jsonb(schedule_day::date) order by schedule_day),'[]'::jsonb
  ) into v_schedule
  from generate_series(
    v_conference.start_date::timestamp,v_conference.end_date::timestamp,
    interval '1 day'
  ) schedule_day;
  return jsonb_build_object(
    'conferenceId',v_conference.id,
    'name',v_conference.name,
    'place',v_conference.place,
    'startDate',v_conference.start_date,
    'endDate',v_conference.end_date,
    'status',v_conference.status,
    'completedAt',v_conference.completed_at,
    'revision',v_conference.revision,
    'createdAt',v_conference.created_at,
    'updatedAt',v_conference.updated_at,
    'updatedBy',v_conference.updated_by,
    'days',case when v_conference.start_date is null then null
      else (v_conference.end_date-v_conference.start_date)+1 end,
    'nights',case when v_conference.start_date is null then null
      else v_conference.end_date-v_conference.start_date end,
    'schedule',v_schedule
  );
end $$;

create or replace function public.list_accessible_conferences(p_actor_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_conference public.conferences%rowtype; v_items jsonb:='[]'::jsonb;
begin
  perform public.require_current_approved_device(p_actor_device_id);
  for v_conference in select conferences.* from public.conferences conferences
    where conferences.deleted_at is null order by conferences.created_at,conferences.id loop
    begin
      perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.access.view','conference',v_conference.id::text);
      v_items:=v_items||jsonb_build_array(jsonb_build_object(
        'conferenceId',v_conference.id,
        'name',v_conference.name,'startDate',v_conference.start_date,'endDate',v_conference.end_date,
        'status',v_conference.status,'completedAt',v_conference.completed_at,'revision',v_conference.revision,
        'createdAt',v_conference.created_at,'updatedAt',v_conference.updated_at));
    exception when insufficient_privilege then null;
    end;
  end loop;
  return jsonb_build_object('conferences',v_items);
end $$;

create or replace function public.create_canonical_conference(
  p_actor_device_id uuid,
  p_operation_id uuid,
  p_requested_conference_id uuid,
  p_name text,
  p_start_date date,
  p_end_date date
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_context jsonb;
  v_actor uuid;
  v_device_authorization_id uuid;
  v_name text:=btrim(coalesce(p_name,''));
  v_intent jsonb;
  v_prior public.conference_creation_operations%rowtype;
  v_permission text;
  v_grant_ids jsonb:='{}'::jsonb;
  v_grant_id uuid;
  v_result jsonb;
begin
  if p_operation_id is null or p_requested_conference_id is null
     or v_name='' or char_length(v_name)>500
     or p_start_date is null or p_end_date is null or p_end_date<p_start_date then
    raise exception 'CANONICAL_CONFERENCE_CREATE_ARGUMENT_INVALID' using errcode='22023';
  end if;

  v_context:=public.require_effective_module_permission(
    p_actor_device_id,'conference','conference.lifecycle.create',null,null
  );
  v_actor:=(v_context->>'actorUserId')::uuid;
  v_device_authorization_id:=platform_private.validated_phase1c_device_authorization(
    v_actor,p_actor_device_id
  );
  if v_device_authorization_id is null then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end if;

  v_intent:=jsonb_build_object(
    'contract','final-canonical-conference-create-v1',
    'conferenceId',p_requested_conference_id,
    'name',v_name,'startDate',p_start_date,'endDate',p_end_date
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_actor::text||':conference-create:'||p_operation_id::text,0)
  );
  select operations.* into v_prior
  from public.conference_creation_operations operations
  where operations.user_id=v_actor and operations.operation_id=p_operation_id;
  if found then
    if v_prior.conference_id<>p_requested_conference_id
       or v_prior.initial_metadata<>v_intent then
      raise exception 'CANONICAL_CONFERENCE_CREATE_OPERATION_MISMATCH' using errcode='22023';
    end if;
    if not exists(
      select 1 from public.conferences conference
      where conference.id=p_requested_conference_id and conference.deleted_at is null
    ) or exists(
      select 1 from (values('conference.access.view'),('conference.lifecycle.manage')) expected(permission_key)
      where not exists(
        select 1 from public.module_permission_grants grants
        where grants.user_id=v_actor and grants.module_key='conference'
          and grants.permission_key=expected.permission_key
          and grants.resource_type='conference'
          and grants.resource_id=p_requested_conference_id::text
          and grants.revoked_at is null
      )
    ) then
      raise exception 'CANONICAL_CONFERENCE_CREATE_REPLAY_STATE_INVALID' using errcode='55000';
    end if;
    return jsonb_build_object(
      'status','duplicate','operationId',p_operation_id,
      'conferenceId',p_requested_conference_id,
      'name',v_name,'startDate',p_start_date,'endDate',p_end_date,
      'conferenceStatus','active','completedAt',null,'revision',1,'created',false
    );
  end if;

  if exists(select 1 from public.conferences where id=p_requested_conference_id) then
    raise exception 'CONFERENCE_ID_ALREADY_USED' using errcode='23505';
  end if;

  insert into public.conferences(
    id,name,owner_id,start_date,end_date,status,
    completed_at,revision,updated_by
  ) values(
    p_requested_conference_id,v_name,v_actor,
    p_start_date,p_end_date,'active',null,1,v_actor
  );

  insert into public.conference_creation_operations(
    user_id,operation_id,conference_id,initial_metadata
  ) values(v_actor,p_operation_id,p_requested_conference_id,v_intent);

  foreach v_permission in array array[
    'conference.access.view','conference.lifecycle.manage'
  ] loop
    insert into public.module_permission_grants(
      user_id,module_key,permission_key,resource_type,resource_id,
      granted_by,granted_by_device_id
    ) values(
      v_actor,'conference',v_permission,'conference',p_requested_conference_id::text,
      v_actor,p_actor_device_id
    ) returning grant_id into v_grant_id;
    v_grant_ids:=v_grant_ids||jsonb_build_object(v_permission,v_grant_id);
  end loop;

  v_result:=jsonb_build_object(
    'status','created','operationId',p_operation_id,
    'conferenceId',p_requested_conference_id,
    'name',v_name,'startDate',p_start_date,'endDate',p_end_date,
    'conferenceStatus','active','completedAt',null,'revision',1,'created',true
  );
  insert into platform.audit_events(
    actor_user_id,actor_device_authorization_id,subject_user_id,
    domain,module,action,entity_type,entity_id,scope_type,scope_id,
    old_values,new_values,metadata,operation_id,source
  ) values(
    v_actor,v_device_authorization_id,null,
    'platform','conference','conference.lifecycle.created',
    'conference',p_requested_conference_id,'platform',null,
    null,jsonb_build_object(
      'name',v_name,'startDate',p_start_date,'endDate',p_end_date,
      'status','active','completedAt',null,'revision',1
    ),jsonb_build_object(
      'permissionKey','conference.lifecycle.create',
      'authoritySource',v_context->>'authoritySource',
      'authorityGrantId',v_context->'grantId',
      'creatorResourceGrants',v_grant_ids,'deviceId',p_actor_device_id
    ),p_operation_id,'rpc'
  );
  return v_result;
end $$;

create or replace function platform_private.route_canonical_conference_operation(
  p_user_id uuid,p_session_id uuid,p_token_hash bytea,p_actor_device_id uuid,
  p_operation text,p_args jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if p_operation='create_canonical_conference' then
    perform platform_private.require_exact_jsonb_keys(p_args,array[
      'p_operation_id','p_requested_conference_id',
      'p_name','p_start_date','p_end_date'
    ]);
    return public.create_canonical_conference(
      p_actor_device_id,(p_args->>'p_operation_id')::uuid,
      (p_args->>'p_requested_conference_id')::uuid,p_args->>'p_name',
      (p_args->>'p_start_date')::date,(p_args->>'p_end_date')::date
    );
  elsif p_operation='mutate_conference_core' then
    perform platform_private.require_exact_jsonb_keys(p_args,array[
      'p_operation_id','p_conference_id','p_expected_revision','p_name',
      'p_place','p_start_date','p_end_date','p_status'
    ]);
    return public.mutate_conference_core(
      p_actor_device_id,(p_args->>'p_operation_id')::uuid,
      (p_args->>'p_conference_id')::uuid,
      (p_args->>'p_expected_revision')::bigint,p_args->>'p_name',
      p_args->>'p_place',(p_args->>'p_start_date')::date,
      (p_args->>'p_end_date')::date,p_args->>'p_status'
    );
  elsif p_operation='list_accessible_conferences' then
    perform platform_private.require_exact_jsonb_keys(p_args,array[]::text[]);
    return public.list_accessible_conferences(p_actor_device_id);
  elsif p_operation='get_conference_core' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_core(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='list_conference_participations' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.list_conference_participations(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='create_conference_participation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_person_id']);
    return public.create_conference_participation(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,(p_args->>'p_person_id')::uuid);
  elsif p_operation='create_conference_participation_with_person' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_full_name','p_phone','p_gender','p_date_of_birth','p_church']);
    return public.create_conference_participation_with_person(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,p_args->>'p_full_name',p_args->>'p_phone',p_args->>'p_gender',(p_args->>'p_date_of_birth')::date,p_args->>'p_church');
  elsif p_operation='set_conference_participation_status' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_participation_id','p_expected_revision','p_status']);
    return public.set_conference_participation_status(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_participation_id')::uuid,(p_args->>'p_expected_revision')::bigint,p_args->>'p_status');
  elsif p_operation='set_conference_participation_guardian' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_participation_id','p_expected_revision','p_guardian_participation_id']);
    return public.set_conference_participation_guardian(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_participation_id')::uuid,(p_args->>'p_expected_revision')::bigint,(p_args->>'p_guardian_participation_id')::uuid);
  elsif p_operation='delete_conference_participation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_participation_id','p_expected_revision']);
    return public.delete_conference_participation(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_participation_id')::uuid,(p_args->>'p_expected_revision')::bigint);
  elsif p_operation='get_conference_accommodation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_accommodation(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation in('create_accommodation_house','update_accommodation_house','delete_accommodation_house','create_accommodation_floor','update_accommodation_floor','delete_accommodation_floor','create_accommodation_room','update_accommodation_room','delete_accommodation_room') then
    return public.mutate_conference_accommodation_structure(p_actor_device_id,replace(p_operation,'_accommodation_','_'),p_args);
  elsif p_operation='assign_conference_accommodation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_room_id','p_participation_id','p_arrival_day','p_leave_day','p_bed_type','p_extra_bed_person_type']);
    return public.assign_conference_accommodation(p_actor_device_id,(p_args->>'p_conference_id')::uuid,(p_args->>'p_room_id')::uuid,(p_args->>'p_participation_id')::uuid,(p_args->>'p_arrival_day')::integer,(p_args->>'p_leave_day')::integer,p_args->>'p_bed_type',p_args->>'p_extra_bed_person_type');
  elsif p_operation='move_conference_accommodation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_occupancy_id','p_expected_revision','p_room_id','p_arrival_day','p_leave_day','p_bed_type','p_extra_bed_person_type']);
    return public.move_conference_accommodation(p_actor_device_id,(p_args->>'p_conference_id')::uuid,(p_args->>'p_occupancy_id')::uuid,(p_args->>'p_expected_revision')::bigint,(p_args->>'p_room_id')::uuid,(p_args->>'p_arrival_day')::integer,(p_args->>'p_leave_day')::integer,p_args->>'p_bed_type',p_args->>'p_extra_bed_person_type');
  elsif p_operation='remove_conference_accommodation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_occupancy_id','p_expected_revision']);
    return public.remove_conference_accommodation(p_actor_device_id,(p_args->>'p_conference_id')::uuid,(p_args->>'p_occupancy_id')::uuid,(p_args->>'p_expected_revision')::bigint);
  elsif p_operation='get_conference_transport' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_transport(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='mutate_conference_transport_vehicle' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_operation','p_conference_id','p_vehicle_id','p_expected_revision','p_name','p_icon','p_capacity','p_position','p_remove_overflow']);
    return public.mutate_conference_transport_vehicle(p_actor_device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_operation',(p_args->>'p_conference_id')::uuid,nullif(p_args->>'p_vehicle_id','')::uuid,nullif(p_args->>'p_expected_revision','')::bigint,p_args->>'p_name',p_args->>'p_icon',nullif(p_args->>'p_capacity','')::integer,nullif(p_args->>'p_position','')::integer,coalesce((p_args->>'p_remove_overflow')::boolean,false));
  elsif p_operation='set_conference_transport_assignment' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_participation_id','p_vehicle_id','p_mode','p_rider_kind','p_seat_number','p_expected_revision']);
    return public.set_conference_transport_assignment(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,(p_args->>'p_participation_id')::uuid,(p_args->>'p_vehicle_id')::uuid,p_args->>'p_mode',p_args->>'p_rider_kind',nullif(p_args->>'p_seat_number','')::integer,nullif(p_args->>'p_expected_revision','')::bigint);
  elsif p_operation='remove_conference_transport_assignment' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_assignment_id','p_expected_revision']);
    return public.remove_conference_transport_assignment(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_assignment_id')::uuid,(p_args->>'p_expected_revision')::bigint);
  elsif p_operation='get_conference_restaurant' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_restaurant(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='mutate_conference_restaurant' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_operation','p_conference_id','p_expected_revision','p_payload']);
    return public.mutate_conference_restaurant(p_actor_device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_operation',(p_args->>'p_conference_id')::uuid,nullif(p_args->>'p_expected_revision','')::bigint,p_args->'p_payload');
  elsif p_operation='mutate_conference_accommodation_pricing' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_expected_revision','p_payload']);
    return public.mutate_conference_accommodation_pricing(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,nullif(p_args->>'p_expected_revision','')::bigint,p_args->'p_payload');
  elsif p_operation='get_conference_air_conditioning' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_air_conditioning(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='mutate_conference_air_conditioning' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_scope','p_scope_id','p_action','p_expected_revision','p_configuration']);
    return public.mutate_conference_air_conditioning(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,p_args->>'p_scope',nullif(p_args->>'p_scope_id','')::uuid,p_args->>'p_action',(p_args->>'p_expected_revision')::bigint,p_args->'p_configuration');
  elsif p_operation='get_conference_finance' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_finance(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='mutate_conference_finance' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_entity','p_action','p_entity_id','p_expected_revision','p_payload']);
    return public.mutate_conference_finance(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,p_args->>'p_entity',p_args->>'p_action',nullif(p_args->>'p_entity_id','')::uuid,(p_args->>'p_expected_revision')::bigint,p_args->'p_payload');
  elsif p_operation='get_conference_branding' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_branding(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='mutate_conference_branding' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_action','p_expected_revision','p_payload']);
    return public.mutate_conference_branding(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,p_args->>'p_action',(p_args->>'p_expected_revision')::bigint,p_args->'p_payload');
  elsif p_operation='list_conference_activity' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.list_conference_activity(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='record_conference_output_event' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_event']);
    return public.record_conference_output_event(p_actor_device_id,(p_args->>'p_conference_id')::uuid,p_args->>'p_event');
  end if;
  return platform.execute_conference_device_operation_phase1c_core(
    p_user_id,p_session_id,p_token_hash,p_operation,p_args
  );
end $$;
revoke all on function public.create_canonical_conference(uuid,uuid,uuid,text,date,date) from public,anon,authenticated,service_role;

-- Idempotency and audit retain actor, device, revision and partition authority.
create or replace function reservations_private.begin_operation(
  p_operation_id uuid,p_context jsonb,p_operation text,p_args jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_prior reservations.operations%rowtype;
  v_partition uuid:=(p_context->>'scopePartitionId')::uuid;
  v_intent text; v_linked_intent text; v_linked_partition boolean:=false;
begin
  if p_operation_id is null then raise exception 'RESERVATIONS_OPERATION_ID_REQUIRED' using errcode='22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('reservations-operation:'||p_operation_id::text,0));
  select * into v_prior from reservations.operations where operation_id=p_operation_id;
  if not found then return null; end if;
  v_intent:=reservations_private.intent(p_operation,v_partition,p_args-'p_operation_id');
  select exists(select 1 from reservations.scope_partition_links link
    where link.old_scope_partition_id=v_prior.scope_partition_id
      and link.new_scope_partition_id=v_partition) into v_linked_partition;
  if v_linked_partition then
    v_linked_intent:=reservations_private.intent(p_operation,v_prior.scope_partition_id,p_args-'p_operation_id');
  end if;
  if v_prior.actor_user_id<>(p_context->>'actorUserId')::uuid
     or v_prior.device_id<>(p_context->>'actorDeviceId')::uuid
     or v_prior.operation_name<>p_operation
     or not ((v_prior.scope_partition_id=v_partition and v_prior.intent_hash=v_intent)
       or (v_linked_partition and v_prior.intent_hash=v_linked_intent)) then
    raise exception 'RESERVATIONS_OPERATION_IDEMPOTENCY_CONFLICT' using errcode='40001';
  end if;
  return v_prior.result;
end $$;

create or replace function reservations_private.complete_operation(
  p_operation_id uuid,p_context jsonb,p_operation text,p_args jsonb,p_result jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
begin
  perform set_config('reservations.scope_partition_id',p_context->>'scopePartitionId',true);
  insert into reservations.operations(
    operation_id,scope_partition_id,actor_user_id,device_id,operation_name,intent_hash,result
  ) values(
    p_operation_id,(p_context->>'scopePartitionId')::uuid,
    (p_context->>'actorUserId')::uuid,(p_context->>'actorDeviceId')::uuid,p_operation,
    reservations_private.intent(p_operation,(p_context->>'scopePartitionId')::uuid,p_args-'p_operation_id'),p_result
  );
  return p_result;
end $$;

create or replace function reservations_private.audit(
  p_context jsonb,p_action text,p_entity_type text,p_entity_id uuid,
  p_operation_id uuid,p_old jsonb,p_new jsonb
) returns void language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=(p_context->>'actorUserId')::uuid;
  v_device uuid:=(p_context->>'actorDeviceId')::uuid;
  v_authorization uuid; v_scope_type text:=p_context->>'scopeType';
  v_partition uuid:=nullif(p_context->>'scopePartitionId','')::uuid; v_metadata jsonb;
begin
  v_authorization:=platform_private.validated_phase1c_device_authorization(v_actor,v_device);
  if v_authorization is null then raise exception 'RESERVATIONS_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  if v_scope_type is null and v_partition is null then
    insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,
      entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source)
    values(v_actor,v_authorization,'platform','reservations',p_action,p_entity_type,p_entity_id,
      'platform',p_old,p_new,jsonb_build_object('deviceId',v_device),p_operation_id,'rpc');
    return;
  end if;
  if v_scope_type not in('conference','standalone') or v_partition is null then
    raise exception 'RESERVATIONS_AUDIT_SCOPE_CONTEXT_INVALID' using errcode='22023';
  end if;
  v_metadata:=jsonb_strip_nulls(jsonb_build_object(
    'reservationsScopeType',v_scope_type,
    'conferenceId',case when v_scope_type='conference' then p_context->>'conferenceId' end,
    'deviceId',v_device));
  perform platform_private.write_scoped_audit_event(v_actor,null,'platform','reservations',p_action,
    p_entity_type,p_entity_id,'reservations',v_partition,p_old,p_new,v_metadata,null,p_operation_id,'rpc');
end $$;

create or replace function reservations_private.effective_capabilities(
  p_device_id uuid,p_args jsonb
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid; v_conference_id uuid; v_is_owner boolean;
begin
  if p_args is null or jsonb_typeof(p_args)<>'object' then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
  v_actor:=public.require_current_approved_device(p_device_id);
  v_is_owner:=platform_private.is_canonical_platform_owner(v_actor);
  if p_args ? 'p_conference_id' and not p_args ? 'p_scope_type' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    v_conference_id:=nullif(p_args->>'p_conference_id','')::uuid;
    if v_conference_id is null or not exists(select 1 from public.conferences c where c.id=v_conference_id and c.deleted_at is null) then
      raise exception 'RESERVATIONS_CONFERENCE_ACCESS_REQUIRED' using errcode='42501';
    end if;
    perform public.require_effective_module_permission(p_device_id,'conference','conference.access.view','conference',v_conference_id::text);
  elsif p_args ? 'p_scope_type' and not p_args ? 'p_conference_id' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_scope_type']);
    if p_args->>'p_scope_type'<>'standalone' then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
  else raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
  return jsonb_build_object('permissions',coalesce((select jsonb_agg(x.permission_key order by x.permission_key)
    from (select permission.code permission_key from platform.permissions permission
      where v_is_owner and permission.domain='reservations' and permission.status='active'
      union select permission.code from platform.permission_grants grant_row
      join platform.permissions permission on permission.id=grant_row.permission_id
      where grant_row.user_id=v_actor and permission.domain='reservations'
        and permission.status='active' and grant_row.revoked_at is null
        and (grant_row.scope_type='module' or (grant_row.scope_type='resource'
          and grant_row.resource_type='event' and exists(select 1 from reservations.events e
            where e.id::text=grant_row.resource_id and ((v_conference_id is null and e.scope_type='standalone'
              and e.conference_id is null) or (v_conference_id is not null and e.scope_type='conference'
              and e.conference_id=v_conference_id and e.scope_partition_id=v_conference_id)))))
    ) x),'[]'::jsonb));
end $$;

drop function if exists reservations_private.context(uuid,uuid,text);
drop function reservations_private.intent(text,uuid,jsonb);
create or replace function reservations_private.intent(
  p_operation text,p_scope_partition_id uuid,p_args jsonb
) returns text language sql immutable set search_path='' as $$
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'operation',p_operation,'scopePartitionId',p_scope_partition_id,'args',p_args
  )::text,'UTF8'),'sha256'),'hex')
$$;

create or replace function reservations_private.create_standalone_event(
  p_device_id uuid,p_args jsonb
) returns jsonb language sql security definer set search_path='' as $$
  select reservations_private.create_standalone_event_scoped(p_device_id,p_args)
$$;

create or replace function reservations.read(
  p_device_id uuid,p_operation text,p_args jsonb
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_context jsonb; v_conference_id uuid; v_event_id uuid;
  v_limit integer:=coalesce((p_args->>'p_limit')::integer,100);
begin
  if p_args is null or jsonb_typeof(p_args)<>'object' then
    raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023';
  end if;
  if p_operation='list_conference_options' then
    perform platform_private.require_exact_jsonb_keys(p_args,array[]::text[]);
    perform reservations_private.booking_target_context(p_device_id);
    return coalesce(public.list_accessible_conferences(p_device_id)->'conferences','[]'::jsonb);
  end if;
  if p_operation='list_events' then
    perform reservations_private.booking_target_context(p_device_id);
    if v_limit<1 or v_limit>5000 then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
    if p_args ? 'p_conference_id' and not p_args ? 'p_scope_type' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_status','p_limit']);
      v_conference_id:=nullif(p_args->>'p_conference_id','')::uuid;
      if v_conference_id is null then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
      perform reservations_private.conference_context(p_device_id,v_conference_id,'reservations.booking.create');
      return (select coalesce(jsonb_agg(to_jsonb(x) order by x.start_date desc,x.id),'[]'::jsonb)
        from (select e.* from reservations.events e where e.scope_type='conference'
          and e.conference_id=v_conference_id and e.scope_partition_id=v_conference_id
          and ((p_args->>'p_status') is null or e.status=p_args->>'p_status')
          order by e.start_date desc,e.id limit v_limit) x);
    elsif p_args ? 'p_scope_type' and not p_args ? 'p_conference_id' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_scope_type','p_status','p_limit']);
      if p_args->>'p_scope_type'<>'standalone' then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
      return (select coalesce(jsonb_agg(to_jsonb(x) order by x.start_date desc,x.id),'[]'::jsonb)
        from (select e.* from reservations.events e where e.scope_type='standalone'
          and e.conference_id is null and ((p_args->>'p_status') is null or e.status=p_args->>'p_status')
          order by e.start_date desc,e.id limit v_limit) x);
    end if;
    raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023';
  end if;
  if p_operation='list_booking_types' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_event_id']);
    v_event_id:=nullif(p_args->>'p_event_id','')::uuid;
    if v_event_id is null then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
    v_context:=reservations_private.resolve_event_scope(p_device_id,v_event_id,'reservations.booking.create');
    return (select coalesce(jsonb_agg(to_jsonb(t) order by t.display_order),'[]'::jsonb)
      from reservations.booking_types t where t.event_id=v_event_id
        and t.scope_partition_id=(v_context->>'scopePartitionId')::uuid);
  end if;
  return reservations_private.read_scoped(p_device_id,p_operation,p_args);
end $$;
create or replace function reservations_private.link_standalone_event_to_conference(
  p_device_id uuid,p_args jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_operation_id uuid:=nullif(p_args->>'p_operation_id','')::uuid;
  v_event_id uuid:=nullif(p_args->>'p_event_id','')::uuid;
  v_conference_id uuid:=nullif(p_args->>'p_conference_id','')::uuid;
  v_expected_revision bigint:=(p_args->>'p_expected_revision')::bigint;
  v_context jsonb; v_replay jsonb; v_event reservations.events%rowtype;
  v_new_event reservations.events%rowtype; v_old_partition uuid; v_new_partition uuid;
  v_actor uuid; v_result jsonb;
begin
  if p_args is null or jsonb_typeof(p_args)<>'object'
     or p_args ?| array['scope_partition_id','p_scope_partition_id',
       'device_id','p_device_id','actor_user_id','p_actor_user_id','actor_device_id','p_actor_device_id'] then
    raise exception 'RESERVATIONS_SCOPE_OVERRIDE_DENIED' using errcode='42501';
  end if;
  perform platform_private.require_exact_jsonb_keys(
    p_args,array['p_operation_id','p_event_id','p_expected_revision','p_conference_id']
  );
  if v_operation_id is null or v_event_id is null or v_conference_id is null then
    raise exception 'RESERVATIONS_LINK_ARGUMENTS_REQUIRED' using errcode='22023';
  end if;
  v_context:=reservations_private.conference_context(
    p_device_id,v_conference_id,'reservations.event.manage'
  );
  v_new_partition:=v_conference_id;
  v_actor:=(v_context->>'actorUserId')::uuid;
  v_context:=v_context||jsonb_build_object(
    'scopeType','conference','scopePartitionId',v_new_partition,'conferenceId',v_conference_id,
    'eventId',v_event_id
  );
  v_replay:=reservations_private.begin_operation(
    v_operation_id,v_context,'link_standalone_event_to_conference',p_args
  );
  if v_replay is not null then return v_replay; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('reservations-link-event:'||v_event_id::text,0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('reservations-link-conference:'||v_conference_id::text,0)
  );
  select * into v_event from reservations.events where id=v_event_id for update;
  if not found then raise exception 'RESERVATIONS_EVENT_NOT_FOUND' using errcode='P0002'; end if;
  if v_event.scope_type<>'standalone' or v_event.conference_id is not null then
    raise exception 'RESERVATIONS_EVENT_NOT_STANDALONE' using errcode='22023';
  end if;
  if v_event.revision<>v_expected_revision then
    raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001';
  end if;
  if exists(select 1 from reservations.events where conference_id=v_conference_id and id<>v_event_id) then
    raise exception 'RESERVATIONS_TARGET_CONFERENCE_ALREADY_HAS_EVENT' using errcode='40001';
  end if;
  v_old_partition:=v_event.scope_partition_id;
  if v_old_partition is null or v_old_partition=v_new_partition then
    raise exception 'RESERVATIONS_SCOPE_PARTITION_INVALID' using errcode='22023';
  end if;
  if exists(select 1 from reservations.scope_partition_links
    where old_scope_partition_id=v_old_partition or event_id=v_event_id or conference_id=v_conference_id) then
    raise exception 'RESERVATIONS_SCOPE_LINK_CONFLICT' using errcode='40001';
  end if;
  if exists(select 1 from reservations.booking_number_counters where scope_partition_id=v_new_partition)
     and exists(select 1 from reservations.booking_number_counters where scope_partition_id=v_old_partition) then
    raise exception 'RESERVATIONS_TARGET_PARTITION_COUNTER_CONFLICT' using errcode='40001';
  end if;
  set constraints all deferred;
  perform set_config('reservations.scope_relink_guard',
    v_event_id::text||':'||v_old_partition::text||':'||v_new_partition::text,true);
  update reservations.events set scope_type='conference',scope_partition_id=v_new_partition,
    conference_id=v_conference_id,revision=revision+1,
    updated_at=statement_timestamp(),updated_by=v_actor where id=v_event_id;
  update reservations.event_periods set scope_partition_id=v_new_partition where scope_partition_id=v_old_partition;
  update reservations.booking_types set scope_partition_id=v_new_partition where scope_partition_id=v_old_partition;
  update reservations.participants set scope_partition_id=v_new_partition where scope_partition_id=v_old_partition;
  update reservations.bookings set scope_partition_id=v_new_partition where scope_partition_id=v_old_partition;
  update reservations.payments set scope_partition_id=v_new_partition where scope_partition_id=v_old_partition;
  update reservations.attendance_records set scope_partition_id=v_new_partition where scope_partition_id=v_old_partition;
  update reservations.operational_reviews set scope_partition_id=v_new_partition where scope_partition_id=v_old_partition;
  update reservations.booking_number_counters set scope_partition_id=v_new_partition where scope_partition_id=v_old_partition;
  insert into reservations.scope_partition_links(
    old_scope_partition_id,new_scope_partition_id,event_id,conference_id,operation_id,linked_by
  ) values(v_old_partition,v_new_partition,v_event_id,v_conference_id,v_operation_id,v_actor);
  select * into v_new_event from reservations.events where id=v_event_id;
  v_result:=jsonb_build_object('eventId',v_event_id,'conferenceId',v_conference_id,
    'scopeType','conference','oldScopePartitionId',v_old_partition,
    'scopePartitionId',v_new_partition,'revision',v_new_event.revision);
  perform reservations_private.audit(v_context,'event.linked_to_conference','event',v_event_id,
    v_operation_id,to_jsonb(v_event),to_jsonb(v_new_event));
  return reservations_private.complete_operation(
    v_operation_id,v_context,'link_standalone_event_to_conference',p_args,v_result
  );
end $$;

create or replace function reservations_private.enforce_event_scope_partition_immutable()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare v_guard text;
begin
  if tg_op='UPDATE' and (new.scope_type,new.scope_partition_id,new.conference_id)
       is distinct from (old.scope_type,old.scope_partition_id,old.conference_id) then
    v_guard:=current_setting('reservations.scope_relink_guard',true);
    if not (
      old.scope_type='standalone'
      and new.scope_type='conference'
      and old.conference_id is null
      and new.conference_id is not null
      and new.scope_partition_id=new.conference_id
      and v_guard=(old.id::text||':'||old.scope_partition_id::text||':'||new.scope_partition_id::text)
    ) then
      raise exception 'RESERVATIONS_EVENT_SCOPE_IMMUTABLE' using errcode='55000';
    end if;
  end if;
  return new;
end $$;

create or replace function reservations_private.protect_payment_history()
returns trigger
language plpgsql
set search_path=''
as $$
declare
  v_guard text;
  v_booking_event_id uuid;
  v_booking_partition uuid;
begin
  if tg_op='DELETE' then
    raise exception 'RESERVATIONS_PAYMENT_DELETE_DENIED' using errcode='55000';
  end if;

  if old.scope_partition_id is distinct from new.scope_partition_id
     and old.booking_id=new.booking_id
     and old.amount=new.amount
     and old.payment_date=new.payment_date
     and old.payment_method=new.payment_method
     and old.payment_method_other is not distinct from new.payment_method_other
     and old.reference is not distinct from new.reference
     and old.notes is not distinct from new.notes
     and old.created_at=new.created_at
     and old.created_by=new.created_by
     and old.created_by_device_id=new.created_by_device_id
     and old.status=new.status then
    v_guard:=current_setting('reservations.scope_relink_guard',true);
    select b.event_id,b.scope_partition_id
      into v_booking_event_id,v_booking_partition
    from reservations.bookings b
    where b.id=new.booking_id;

    if v_booking_event_id is not null
       and v_booking_partition=new.scope_partition_id
       and v_guard=(v_booking_event_id::text||':'||old.scope_partition_id::text||':'||new.scope_partition_id::text) then
      return new;
    end if;
  end if;
  if old.booking_id<>new.booking_id
     or old.amount<>new.amount
     or old.payment_date<>new.payment_date
     or old.payment_method<>new.payment_method
     or old.payment_method_other is distinct from new.payment_method_other
     or old.reference is distinct from new.reference
     or old.notes is distinct from new.notes
     or old.created_at<>new.created_at
     or old.created_by<>new.created_by
     or old.created_by_device_id<>new.created_by_device_id
     or old.status<>'active'
     or new.status<>'voided' then
    raise exception 'RESERVATIONS_PAYMENT_IMMUTABLE' using errcode='55000';
  end if;

  return new;
end $$;
create or replace function reservations_private.create_event_authorized(
  p_device_id uuid,p_args jsonb
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_context jsonb; v_replay jsonb; v_result jsonb; v_actor uuid; v_partition uuid;
        v_event_id uuid; v_revision bigint; v_operation_id uuid:=(p_args->>'p_operation_id')::uuid;
begin
  if p_args->>'p_scope_type'='standalone' then
    perform reservations_private.standalone_create_business_args(p_args-'p_scope_type');
    v_context:=public.require_effective_module_permission(
      p_device_id,'reservations','reservations.event.create',null,null
    )||jsonb_build_object('scopeType','standalone');
    v_replay:=reservations_private.begin_standalone_create(v_operation_id,v_context,p_args-'p_scope_type');
    if v_replay is not null then return v_replay; end if;
    v_partition:=extensions.gen_random_uuid();
    v_context:=v_context||jsonb_build_object('scopePartitionId',v_partition);
  elsif p_args->>'p_scope_type'='conference' and nullif(p_args->>'p_conference_id','')::uuid is not null then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_scope_type','p_conference_id','p_name','p_start_date','p_end_date','p_location','p_capacity','p_status','p_notes']);
    v_context:=reservations_private.conference_context(
      p_device_id,(p_args->>'p_conference_id')::uuid,'reservations.event.create'
    );
    v_replay:=reservations_private.begin_operation(v_operation_id,v_context,'create_event',p_args);
    if v_replay is not null then return v_replay; end if;
    v_partition:=(v_context->>'scopePartitionId')::uuid;
  else raise exception 'RESERVATIONS_CREATE_EVENT_SCOPE_INVALID' using errcode='22023'; end if;
  v_actor:=(v_context->>'actorUserId')::uuid;
  insert into reservations.events(
    scope_type,scope_partition_id,conference_id,name,start_date,end_date,
    location,capacity,status,notes,created_by,updated_by
  ) values(
    p_args->>'p_scope_type',v_partition,nullif(p_args->>'p_conference_id','')::uuid,btrim(p_args->>'p_name'),
    (p_args->>'p_start_date')::date,(p_args->>'p_end_date')::date,
    coalesce(p_args->>'p_location',''),(p_args->>'p_capacity')::integer,
    p_args->>'p_status',coalesce(p_args->>'p_notes',''),v_actor,v_actor
  ) returning id,revision into v_event_id,v_revision;
  perform platform_private.grant_deterministic_resource_permission(
    v_context,v_operation_id,v_event_id
  );
  v_result:=jsonb_build_object('eventId',v_event_id,'revision',v_revision,
    'scopeType',p_args->>'p_scope_type','scopePartitionId',v_partition,
    'event',(select to_jsonb(e) from reservations.events e where e.id=v_event_id));
  perform reservations_private.audit(v_context,'event.created','event',v_event_id,v_operation_id,null,v_result);
  if p_args->>'p_scope_type'='standalone' then
    return reservations_private.complete_standalone_create(v_operation_id,v_context,p_args-'p_scope_type',v_result);
  end if;
  return reservations_private.complete_operation(v_operation_id,v_context,'create_event',p_args,v_result);
end $$;

create or replace function reservations_private.standalone_create_business_args(p_args jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
begin
 if p_args is null or jsonb_typeof(p_args)<>'object'
    or p_args ?| array['scope_partition_id','p_scope_partition_id','device_id','p_device_id','actor_user_id','p_actor_user_id','actor_device_id','p_actor_device_id'] then
   raise exception 'RESERVATIONS_SCOPE_OVERRIDE_DENIED' using errcode='42501';
 end if;
 if not p_args ?& array['p_operation_id','p_name','p_start_date','p_end_date','p_location','p_capacity','p_status','p_notes']
    or p_args - array['p_operation_id','p_name','p_start_date','p_end_date','p_location','p_capacity','p_status','p_notes'] <> '{}'::jsonb then
   raise exception 'RESERVATIONS_STANDALONE_CREATE_ARGUMENTS_INVALID' using errcode='22023';
 end if;
 return jsonb_build_object(
   'name',btrim(p_args->>'p_name'),
   'startDate',((p_args->>'p_start_date')::date)::text,
   'endDate',((p_args->>'p_end_date')::date)::text,
   'location',coalesce(p_args->>'p_location',''),
   'capacity',(p_args->>'p_capacity')::integer,
   'status',p_args->>'p_status',
   'notes',coalesce(p_args->>'p_notes','')
 );
end $$;

create or replace function reservations_private.complete_standalone_create(p_operation_id uuid,p_context jsonb,p_args jsonb,p_result jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform set_config('reservations.scope_partition_id',(p_context->>'scopePartitionId'),true);
 insert into reservations.operations(operation_id,scope_partition_id,actor_user_id,device_id,operation_name,intent_hash,result)
 values(p_operation_id,(p_context->>'scopePartitionId')::uuid,(p_context->>'actorUserId')::uuid,(p_context->>'actorDeviceId')::uuid,'create_event',reservations_private.standalone_create_intent(p_args),p_result);
 return p_result;
end $$;

create or replace function reservations_private.create_standalone_event_scoped(p_device_id uuid,p_args jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_context jsonb; v_partition uuid; v_actor uuid; v_replay jsonb; v_id uuid; v_revision bigint; v_result jsonb; v_operation_id uuid:=(p_args->>'p_operation_id')::uuid;
begin
 perform reservations_private.standalone_create_business_args(p_args);
 v_context:=public.require_effective_module_permission(p_device_id,'reservations','reservations.event.manage',null,null)||jsonb_build_object('scopeType','standalone');
 v_actor:=(v_context->>'actorUserId')::uuid;
 v_replay:=reservations_private.begin_standalone_create(v_operation_id,v_context,p_args);
 if v_replay is not null then return v_replay; end if;
 v_partition:=extensions.gen_random_uuid();
 v_context:=v_context||jsonb_build_object('scopePartitionId',v_partition);
 insert into reservations.events(scope_type,scope_partition_id,conference_id,name,start_date,end_date,location,capacity,status,notes,created_by,updated_by)
 values('standalone',v_partition,null,btrim(p_args->>'p_name'),(p_args->>'p_start_date')::date,(p_args->>'p_end_date')::date,coalesce(p_args->>'p_location',''),(p_args->>'p_capacity')::integer,p_args->>'p_status',coalesce(p_args->>'p_notes',''),v_actor,v_actor)
 returning id,revision into v_id,v_revision;
 v_result:=jsonb_build_object('eventId',v_id,'revision',v_revision,'scopeType','standalone','scopePartitionId',v_partition);
 perform reservations_private.audit(v_context,'event.created','event',v_id,v_operation_id,null,v_result);
 return reservations_private.complete_standalone_create(v_operation_id,v_context,p_args,v_result);
end $$;
commit;
