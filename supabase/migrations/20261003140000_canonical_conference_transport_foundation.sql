begin;

do $$ begin
  if to_regclass('public.conferences') is null or to_regclass('public.conference_participations') is null
     or to_regclass('platform.people') is null or to_regclass('platform.audit_events') is null
     or to_regprocedure('public.require_effective_module_permission(uuid,text,text,text,text)') is null
     or to_regprocedure('platform_private.validated_phase1c_device_authorization(uuid,uuid)') is null
     or to_regprocedure('platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)') is null then
    raise exception 'P6I_B2_CANONICAL_FOUNDATION_REQUIRED' using errcode='55000';
  end if;
  if not exists(select 1 from public.module_permission_catalog where permission_key='conference.transport.view' and module_key='conference' and status='active')
     or not exists(select 1 from public.module_permission_catalog where permission_key='conference.transport.manage' and module_key='conference' and status='active') then
    raise exception 'P6I_B2_TRANSPORT_PERMISSION_CONTRACT_REQUIRED' using errcode='55000';
  end if;
end $$;

create table public.conference_transport_vehicles(
  id uuid primary key default extensions.gen_random_uuid(), conference_id uuid not null references public.conferences(id) on delete cascade,
  name text not null check(length(btrim(name)) between 1 and 160), icon text not null default '🚌' check(length(icon)<=32),
  capacity integer not null check(capacity between 1 and 300), position integer not null default 0 check(position>=0),
  revision bigint not null default 1 check(revision>=1), created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(), created_by uuid not null references platform.profiles(user_id),
  updated_by uuid not null references platform.profiles(user_id), unique(conference_id,id), unique(conference_id,name)
);
create index conference_transport_vehicles_list_idx on public.conference_transport_vehicles(conference_id,position,id);

create table public.conference_transport_assignments(
  id uuid primary key default extensions.gen_random_uuid(), conference_id uuid not null references public.conferences(id) on delete cascade,
  vehicle_id uuid not null, participation_id uuid not null,
  assignment_mode text not null check(assignment_mode in('independent','shared')),
  rider_kind text not null check(rider_kind in('adult','child','infant')),
  seat_number integer check(seat_number between 1 and 300), revision bigint not null default 1 check(revision>=1),
  created_at timestamptz not null default statement_timestamp(), updated_at timestamptz not null default statement_timestamp(),
  created_by uuid not null references platform.profiles(user_id), updated_by uuid not null references platform.profiles(user_id),
  foreign key(conference_id,vehicle_id) references public.conference_transport_vehicles(conference_id,id) on delete cascade,
  foreign key(participation_id,conference_id) references public.conference_participations(id,conference_id) on delete cascade,
  unique(conference_id,participation_id),
  check((assignment_mode='independent' and seat_number is not null) or (assignment_mode='shared' and seat_number is null))
);
create unique index conference_transport_unique_seat_idx on public.conference_transport_assignments(vehicle_id,seat_number) where seat_number is not null;
create index conference_transport_assignments_list_idx on public.conference_transport_assignments(conference_id,vehicle_id,seat_number,id);

create table public.conference_transport_operations(
  actor_user_id uuid not null references platform.profiles(user_id), operation_id uuid not null, operation text not null,
  request jsonb not null check(jsonb_typeof(request)='object'), result jsonb not null check(jsonb_typeof(result)='object'),
  created_at timestamptz not null default statement_timestamp(), primary key(actor_user_id,operation_id)
);

alter table public.conference_transport_vehicles enable row level security; alter table public.conference_transport_vehicles force row level security;
alter table public.conference_transport_assignments enable row level security; alter table public.conference_transport_assignments force row level security;
alter table public.conference_transport_operations enable row level security; alter table public.conference_transport_operations force row level security;
revoke all on table public.conference_transport_vehicles,public.conference_transport_assignments,public.conference_transport_operations from public,anon,authenticated,service_role;

create function platform_private.require_conference_transport_context(p_device uuid,p_conference uuid,p_permission text,p_mutation boolean)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c jsonb; actor uuid; conf public.conferences%rowtype;
begin
  if p_permission not in('conference.transport.view','conference.transport.manage') then raise exception 'CONFERENCE_TRANSPORT_ARGUMENT_INVALID' using errcode='22023'; end if;
  c:=public.require_effective_module_permission(p_device,'conference',p_permission,'conference',p_conference::text); actor:=(c->>'actorUserId')::uuid;
  if platform_private.validated_phase1c_device_authorization(actor,p_device) is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  select * into conf from public.conferences where id=p_conference and deleted_at is null;
  if not found then raise exception 'CONFERENCE_NOT_FOUND' using errcode='P0002'; end if;
  if p_mutation and conf.status<>'active' then raise exception 'COMPLETED_CONFERENCE_IMMUTABLE' using errcode='55000'; end if;
  return c;
end $$;

create function public.get_conference_transport(p_actor_device_id uuid,p_conference_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c jsonb; vehicles jsonb; assignments jsonb; can_manage boolean:=false;
begin
  c:=platform_private.require_conference_transport_context(p_actor_device_id,p_conference_id,'conference.transport.view',false);
  begin
    perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.transport.manage','conference',p_conference_id::text);
    can_manage:=true;
  exception when insufficient_privilege then null;
  end;
  select coalesce(jsonb_agg(jsonb_build_object('vehicleId',v.id,'name',v.name,'icon',v.icon,'capacity',v.capacity,'position',v.position,'revision',v.revision) order by v.position,v.id),'[]') into vehicles from public.conference_transport_vehicles v where v.conference_id=p_conference_id;
  select coalesce(jsonb_agg(jsonb_build_object('assignmentId',a.id,'vehicleId',a.vehicle_id,'participationId',a.participation_id,'mode',a.assignment_mode,'riderKind',a.rider_kind,'seatNumber',a.seat_number,'revision',a.revision,'participationStatus',p.status,'person',jsonb_build_object('personId',p.person_id,'fullName',person.full_name,'phone',person.phone),'guardianParticipationId',p.guardian_participation_id,'guardianParticipationStatus',gp.status,'guardianFullName',gperson.full_name,'roomNumber',room.room_number,'sharingEligible',a.assignment_mode<>'shared' or gp.status='active') order by a.vehicle_id,a.seat_number nulls last,a.id),'[]') into assignments
  from public.conference_transport_assignments a join public.conference_participations p on p.id=a.participation_id
  join platform.people person on person.id=p.person_id left join public.conference_participations gp on gp.id=p.guardian_participation_id
  left join platform.people gperson on gperson.id=gp.person_id left join public.conference_accommodation_occupancies o on o.participation_id=p.id
  left join public.conference_accommodation_rooms room on room.id=o.room_id where a.conference_id=p_conference_id;
  return jsonb_build_object('conferenceId',p_conference_id,'canManage',can_manage,'vehicles',vehicles,'assignments',assignments);
end $$;

create function platform_private.transport_replay(p_actor uuid,p_operation_id uuid,p_operation text,p_request jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$ declare prior public.conference_transport_operations%rowtype; begin
  perform pg_advisory_xact_lock(hashtextextended(p_actor::text||':conference-transport:'||p_operation_id::text,0));
  select * into prior from public.conference_transport_operations where actor_user_id=p_actor and operation_id=p_operation_id;
  if found then if prior.operation<>p_operation or prior.request<>p_request then raise exception 'CONFERENCE_TRANSPORT_OPERATION_MISMATCH' using errcode='22023'; end if; return prior.result; end if; return null;
end $$;

create function public.mutate_conference_transport_vehicle(p_device uuid,p_operation_id uuid,p_operation text,p_conference uuid,p_vehicle uuid,p_expected_revision bigint,p_name text,p_icon text,p_capacity integer,p_position integer,p_remove_overflow boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c jsonb; actor uuid; authz uuid; req jsonb; replay jsonb; old public.conference_transport_vehicles%rowtype; row public.conference_transport_vehicles%rowtype; result jsonb;
begin
  if p_operation_id is null or p_operation not in('create','update','delete') then raise exception 'CONFERENCE_TRANSPORT_ARGUMENT_INVALID' using errcode='22023'; end if;
  c:=platform_private.require_conference_transport_context(p_device,p_conference,'conference.transport.manage',true); actor:=(c->>'actorUserId')::uuid; authz:=platform_private.validated_phase1c_device_authorization(actor,p_device);
  req:=jsonb_build_object('operation',p_operation,'conferenceId',p_conference,'vehicleId',p_vehicle,'expectedRevision',p_expected_revision,'name',p_name,'icon',p_icon,'capacity',p_capacity,'position',p_position,'removeOverflow',p_remove_overflow); replay:=platform_private.transport_replay(actor,p_operation_id,'vehicle_'||p_operation,req); if replay is not null then return replay; end if;
  if p_operation='create' then insert into public.conference_transport_vehicles(conference_id,name,icon,capacity,position,created_by,updated_by) values(p_conference,btrim(p_name),coalesce(nullif(p_icon,''),'🚌'),p_capacity,coalesce(p_position,0),actor,actor) returning * into row;
  else select * into old from public.conference_transport_vehicles where id=p_vehicle and conference_id=p_conference for update; if not found then raise exception 'CONFERENCE_TRANSPORT_VEHICLE_NOT_FOUND' using errcode='P0002'; end if; if old.revision<>p_expected_revision then raise exception 'CONFERENCE_TRANSPORT_REVISION_CONFLICT' using errcode='40001'; end if;
    if p_operation='delete' then delete from public.conference_transport_vehicles where id=p_vehicle; row:=old;
    else if p_capacity<old.capacity and exists(select 1 from public.conference_transport_assignments where vehicle_id=p_vehicle and seat_number>p_capacity) and not coalesce(p_remove_overflow,false) then raise exception 'CONFERENCE_TRANSPORT_CAPACITY_OCCUPIED' using errcode='23514'; end if; if p_capacity<old.capacity then delete from public.conference_transport_assignments where vehicle_id=p_vehicle and seat_number>p_capacity; end if; update public.conference_transport_vehicles set name=btrim(p_name),icon=coalesce(nullif(p_icon,''),'🚌'),capacity=p_capacity,position=coalesce(p_position,position),revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=p_vehicle returning * into row; end if;
  end if;
  result:=jsonb_build_object('vehicleId',row.id,'conferenceId',row.conference_id,'name',row.name,'icon',row.icon,'capacity',row.capacity,'position',row.position,'revision',row.revision,'deleted',p_operation='delete'); insert into public.conference_transport_operations values(actor,p_operation_id,'vehicle_'||p_operation,req,result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source) values(actor,authz,'platform','conference','conference.transport.vehicle_'||p_operation,'conference_transport_vehicle',row.id,'platform',case when p_operation='create' then null else to_jsonb(old) end,case when p_operation='delete' then null else to_jsonb(row) end,jsonb_build_object('conferenceId',p_conference,'permissionKey','conference.transport.manage'),p_operation_id,'rpc'); return result;
end $$;

create function public.set_conference_transport_assignment(p_device uuid,p_operation_id uuid,p_conference uuid,p_participation uuid,p_vehicle uuid,p_mode text,p_rider_kind text,p_seat integer,p_expected_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c jsonb; actor uuid; authz uuid; req jsonb; replay jsonb; part public.conference_participations%rowtype; guardian public.conference_participations%rowtype; vehicle public.conference_transport_vehicles%rowtype; old public.conference_transport_assignments%rowtype; row public.conference_transport_assignments%rowtype; result jsonb;
begin
  c:=platform_private.require_conference_transport_context(p_device,p_conference,'conference.transport.manage',true); actor:=(c->>'actorUserId')::uuid; authz:=platform_private.validated_phase1c_device_authorization(actor,p_device);
  req:=jsonb_build_object('conferenceId',p_conference,'participationId',p_participation,'vehicleId',p_vehicle,'mode',p_mode,'riderKind',p_rider_kind,'seatNumber',p_seat,'expectedRevision',p_expected_revision); replay:=platform_private.transport_replay(actor,p_operation_id,'set_assignment',req); if replay is not null then return replay; end if;
  select * into part from public.conference_participations where id=p_participation and conference_id=p_conference for key share; if not found or part.status<>'active' then raise exception 'CONFERENCE_TRANSPORT_PARTICIPATION_INELIGIBLE' using errcode='23514'; end if;
  select * into vehicle from public.conference_transport_vehicles where id=p_vehicle and conference_id=p_conference for update; if not found then raise exception 'CONFERENCE_TRANSPORT_VEHICLE_NOT_FOUND' using errcode='P0002'; end if;
  if p_mode='independent' then if p_seat is null or p_seat>vehicle.capacity then raise exception 'CONFERENCE_TRANSPORT_SEAT_INVALID' using errcode='23514'; end if;
  elsif p_mode='shared' then select * into guardian from public.conference_participations where id=part.guardian_participation_id and conference_id=p_conference; if not found or guardian.status<>'active' or not exists(select 1 from public.conference_transport_assignments where participation_id=guardian.id and vehicle_id=p_vehicle and assignment_mode='independent') then raise exception 'CONFERENCE_TRANSPORT_GUARDIAN_INELIGIBLE' using errcode='23514'; end if; p_seat:=null;
  else raise exception 'CONFERENCE_TRANSPORT_MODE_INVALID' using errcode='22023'; end if;
  select * into old from public.conference_transport_assignments where conference_id=p_conference and participation_id=p_participation for update;
  if found then if p_expected_revision is null or old.revision<>p_expected_revision then raise exception 'CONFERENCE_TRANSPORT_REVISION_CONFLICT' using errcode='40001'; end if; update public.conference_transport_assignments set vehicle_id=p_vehicle,assignment_mode=p_mode,rider_kind=p_rider_kind,seat_number=p_seat,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=old.id returning * into row;
  else insert into public.conference_transport_assignments(conference_id,vehicle_id,participation_id,assignment_mode,rider_kind,seat_number,created_by,updated_by) values(p_conference,p_vehicle,p_participation,p_mode,p_rider_kind,p_seat,actor,actor) returning * into row; end if;
  if row.assignment_mode='independent' then
    update public.conference_transport_assignments child_assignment set vehicle_id=row.vehicle_id,revision=child_assignment.revision+1,updated_at=statement_timestamp(),updated_by=actor
    from public.conference_participations child where child.id=child_assignment.participation_id and child.guardian_participation_id=row.participation_id and child_assignment.assignment_mode='shared' and child_assignment.conference_id=row.conference_id and child_assignment.vehicle_id<>row.vehicle_id;
  end if;
  result:=jsonb_build_object('assignmentId',row.id,'conferenceId',row.conference_id,'vehicleId',row.vehicle_id,'participationId',row.participation_id,'mode',row.assignment_mode,'riderKind',row.rider_kind,'seatNumber',row.seat_number,'revision',row.revision); insert into public.conference_transport_operations values(actor,p_operation_id,'set_assignment',req,result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source) values(actor,authz,'platform','conference','conference.transport.assignment_set','conference_transport_assignment',row.id,'platform',case when old.id is null then null else to_jsonb(old) end,to_jsonb(row),jsonb_build_object('conferenceId',p_conference,'permissionKey','conference.transport.manage'),p_operation_id,'rpc'); return result;
end $$;

create function public.remove_conference_transport_assignment(p_device uuid,p_operation_id uuid,p_assignment uuid,p_expected_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare old public.conference_transport_assignments%rowtype; c jsonb; actor uuid; authz uuid; req jsonb; replay jsonb; result jsonb;
begin select * into old from public.conference_transport_assignments where id=p_assignment; if not found then raise exception 'CONFERENCE_TRANSPORT_ASSIGNMENT_NOT_FOUND' using errcode='P0002'; end if; c:=platform_private.require_conference_transport_context(p_device,old.conference_id,'conference.transport.manage',true); actor:=(c->>'actorUserId')::uuid; authz:=platform_private.validated_phase1c_device_authorization(actor,p_device); req:=jsonb_build_object('assignmentId',p_assignment,'expectedRevision',p_expected_revision); replay:=platform_private.transport_replay(actor,p_operation_id,'remove_assignment',req); if replay is not null then return replay; end if; select * into old from public.conference_transport_assignments where id=p_assignment for update; if old.revision<>p_expected_revision then raise exception 'CONFERENCE_TRANSPORT_REVISION_CONFLICT' using errcode='40001'; end if; if old.assignment_mode='independent' then delete from public.conference_transport_assignments child_assignment using public.conference_participations child where child.id=child_assignment.participation_id and child.guardian_participation_id=old.participation_id and child_assignment.assignment_mode='shared' and child_assignment.vehicle_id=old.vehicle_id; end if; delete from public.conference_transport_assignments where id=p_assignment; result:=jsonb_build_object('assignmentId',p_assignment,'conferenceId',old.conference_id,'deleted',true); insert into public.conference_transport_operations values(actor,p_operation_id,'remove_assignment',req,result,statement_timestamp()); insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,metadata,operation_id,source) values(actor,authz,'platform','conference','conference.transport.assignment_removed','conference_transport_assignment',old.id,'platform',to_jsonb(old),jsonb_build_object('conferenceId',old.conference_id,'permissionKey','conference.transport.manage'),p_operation_id,'rpc'); return result; end $$;

revoke all on function platform_private.require_conference_transport_context(uuid,uuid,text,boolean),platform_private.transport_replay(uuid,uuid,text,jsonb),public.get_conference_transport(uuid,uuid),public.mutate_conference_transport_vehicle(uuid,uuid,text,uuid,uuid,bigint,text,text,integer,integer,boolean),public.set_conference_transport_assignment(uuid,uuid,uuid,uuid,uuid,text,text,integer,bigint),public.remove_conference_transport_assignment(uuid,uuid,uuid,bigint) from public,anon,authenticated,service_role;

do $$ declare sig regprocedure:='platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)'::regprocedure; d text; marker text:='if p_operation=''list_accessible_conferences'' then'; branch text:='if p_operation=''get_conference_transport'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_conference_id'']); return public.get_conference_transport(p_actor_device_id,(p_args->>''p_conference_id'')::uuid); elsif p_operation=''mutate_conference_transport_vehicle'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_operation'',''p_conference_id'',''p_vehicle_id'',''p_expected_revision'',''p_name'',''p_icon'',''p_capacity'',''p_position'',''p_remove_overflow'']); return public.mutate_conference_transport_vehicle(p_actor_device_id,(p_args->>''p_operation_id'')::uuid,p_args->>''p_operation'',(p_args->>''p_conference_id'')::uuid,nullif(p_args->>''p_vehicle_id'','''')::uuid,nullif(p_args->>''p_expected_revision'','''')::bigint,p_args->>''p_name'',p_args->>''p_icon'',nullif(p_args->>''p_capacity'','''')::integer,nullif(p_args->>''p_position'','''')::integer,coalesce((p_args->>''p_remove_overflow'')::boolean,false)); elsif p_operation=''set_conference_transport_assignment'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_conference_id'',''p_participation_id'',''p_vehicle_id'',''p_mode'',''p_rider_kind'',''p_seat_number'',''p_expected_revision'']); return public.set_conference_transport_assignment(p_actor_device_id,(p_args->>''p_operation_id'')::uuid,(p_args->>''p_conference_id'')::uuid,(p_args->>''p_participation_id'')::uuid,(p_args->>''p_vehicle_id'')::uuid,p_args->>''p_mode'',p_args->>''p_rider_kind'',nullif(p_args->>''p_seat_number'','''')::integer,nullif(p_args->>''p_expected_revision'','''')::bigint); elsif p_operation=''remove_conference_transport_assignment'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_assignment_id'',''p_expected_revision'']); return public.remove_conference_transport_assignment(p_actor_device_id,(p_args->>''p_operation_id'')::uuid,(p_args->>''p_assignment_id'')::uuid,(p_args->>''p_expected_revision'')::bigint); elsif p_operation=''list_accessible_conferences'' then'; begin d:=pg_get_functiondef(sig); if position('p_operation=''get_conference_transport''' in d)<>0 or position(marker in d)=0 then raise exception 'P6I_B2_ROUTER_PRECONDITION_FAILED' using errcode='55000'; end if; execute replace(d,marker,branch); end $$;

create or replace function public.list_accessible_conferences(p_actor_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_conference public.conferences%rowtype; v_items jsonb:='[]'::jsonb; v_can_sync boolean; v_can_accommodation_manage boolean; v_can_transport_manage boolean;
begin
  perform public.require_current_approved_device(p_actor_device_id);
  for v_conference in select conferences.* from public.conferences conferences where conferences.deleted_at is null order by conferences.created_at,conferences.id loop
    begin
      perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.access.view','conference',v_conference.id::text);
      v_can_sync:=false;v_can_accommodation_manage:=false;v_can_transport_manage:=false;
      begin perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.sync.write','conference',v_conference.id::text);v_can_sync:=true;exception when insufficient_privilege then null;end;
      begin perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.accommodation.manage','conference',v_conference.id::text);v_can_accommodation_manage:=true;exception when insufficient_privilege then null;end;
      begin perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.transport.manage','conference',v_conference.id::text);v_can_transport_manage:=true;exception when insufficient_privilege then null;end;
      v_items:=v_items||jsonb_build_array(jsonb_build_object('conferenceId',v_conference.id,'organizationId',v_conference.organization_id,'name',v_conference.name,'startDate',v_conference.start_date,'endDate',v_conference.end_date,'status',v_conference.status,'completedAt',v_conference.completed_at,'revision',v_conference.revision,'createdAt',v_conference.created_at,'updatedAt',v_conference.updated_at,'capabilities',jsonb_build_object('edit',v_can_sync and v_can_accommodation_manage,'sync',v_can_sync,'transportManage',v_can_transport_manage)));
    exception when insufficient_privilege then null;end;
  end loop;
  return jsonb_build_object('conferences',v_items);
end $$;

revoke all on function public.list_accessible_conferences(uuid) from public,anon,authenticated,service_role;

comment on function public.get_conference_transport(uuid,uuid) is 'Protected canonical Transport projection. Participation is sufficient for assignment; Accommodation is optional derived display data.';
comment on table public.conference_transport_assignments is 'Canonical Transport assignment by Conference Participation. No Accommodation occupancy is required or created.';

commit;
