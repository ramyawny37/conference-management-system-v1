begin;
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
commit;
