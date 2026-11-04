begin;
create or replace function reservations_private.conference_context(p_device_id uuid,p_conference_id uuid,p_permission text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_context jsonb;v_organization_id uuid;
begin
 v_context:=public.require_effective_module_permission(p_device_id,'reservations',p_permission,null,null);
 select c.organization_id into v_organization_id from public.conferences c where c.id=p_conference_id and c.deleted_at is null;
 if not found then raise exception 'RESERVATIONS_CONFERENCE_ACCESS_REQUIRED' using errcode='42501'; end if;
 return v_context||jsonb_build_object('conferenceId',p_conference_id,'organizationId',v_organization_id,'scopeType','conference','scopePartitionId',p_conference_id);
end $$;
create or replace function reservations_private.resolve_event_scope(p_device_id uuid,p_event_id uuid,p_permission text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_event reservations.events%rowtype;v_context jsonb;
begin
 select * into v_event from reservations.events where id=p_event_id;
 if not found then raise exception 'RESERVATIONS_EVENT_NOT_FOUND' using errcode='P0002'; end if;
 if p_permission='reservations.reports.view' then v_context:=public.require_effective_module_permission(p_device_id,'reservations',p_permission,null,null);
 else v_context:=public.require_effective_module_permission(p_device_id,'reservations',p_permission,'event',p_event_id::text); end if;
 if v_event.scope_type='conference' then
  if not exists(select 1 from public.conferences c where c.id=v_event.conference_id and c.deleted_at is null) then raise exception 'RESERVATIONS_CONFERENCE_ACCESS_REQUIRED' using errcode='42501'; end if;
 elsif v_event.scope_type<>'standalone' then raise exception 'RESERVATIONS_SCOPE_TYPE_INVALID' using errcode='22023'; end if;
 return v_context||jsonb_build_object('scopeType',v_event.scope_type,'scopePartitionId',v_event.scope_partition_id,'eventId',v_event.id,'conferenceId',v_event.conference_id,'organizationId',case when v_event.scope_type='conference' then v_event.organization_id end);
end $$;
create or replace function reservations_private.effective_capabilities(p_device_id uuid,p_args jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid;v_conference_id uuid;v_is_owner boolean;
begin
 if p_args is null or jsonb_typeof(p_args)<>'object' then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
 v_actor:=public.require_current_approved_device(p_device_id);v_is_owner:=platform_private.is_canonical_platform_owner(v_actor);
 if p_args ? 'p_conference_id' and not p_args ? 'p_scope_type' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);v_conference_id:=nullif(p_args->>'p_conference_id','')::uuid;
  if v_conference_id is null or not exists(select 1 from public.conferences c where c.id=v_conference_id and c.deleted_at is null) then raise exception 'RESERVATIONS_CONFERENCE_ACCESS_REQUIRED' using errcode='42501'; end if;
 elsif p_args ? 'p_scope_type' and not p_args ? 'p_conference_id' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_scope_type']);if p_args->>'p_scope_type'<>'standalone' then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
 else raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
 return jsonb_build_object('permissions',coalesce((select jsonb_agg(x.permission_key order by x.permission_key) from (
  select permission.code permission_key from platform.permissions permission where v_is_owner and permission.domain='reservations' and permission.status='active'
  union select permission.code from platform.permission_grants grant_row join platform.permissions permission on permission.id=grant_row.permission_id
  where grant_row.user_id=v_actor and permission.domain='reservations' and permission.status='active' and grant_row.revoked_at is null
  and (grant_row.scope_type='module' or (grant_row.scope_type='resource' and grant_row.resource_type='event' and exists(
   select 1 from reservations.events e where e.id::text=grant_row.resource_id and ((v_conference_id is null and e.scope_type='standalone' and e.conference_id is null) or (v_conference_id is not null and e.scope_type='conference' and e.conference_id=v_conference_id))
  )))
 ) x),'[]'::jsonb));
end $$;
create or replace function reservations_private.booking_creation_context(p_device_id uuid,p_args jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid;v_conference_id uuid;
begin
 if p_args is null or jsonb_typeof(p_args)<>'object' then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
 v_actor:=public.require_current_approved_device(p_device_id);
 if p_args ? 'p_conference_id' and not p_args ? 'p_scope_type' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);v_conference_id:=nullif(p_args->>'p_conference_id','')::uuid;
  if v_conference_id is null or not exists(select 1 from public.conferences c where c.id=v_conference_id and c.deleted_at is null) then raise exception 'RESERVATIONS_CONFERENCE_ACCESS_REQUIRED' using errcode='42501'; end if;
 elsif p_args ? 'p_scope_type' and not p_args ? 'p_conference_id' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_scope_type']);if p_args->>'p_scope_type'<>'standalone' then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
 else raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'conference_id',e.conference_id,'name',e.name,'start_date',e.start_date,'end_date',e.end_date,'location',e.location,'capacity',e.capacity,'status',e.status,'notes','','revision',e.revision,'bookingTypes',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'event_id',t.event_id,'name',t.name,'code',t.code,'price',t.price,'active',t.active,'display_order',t.display_order,'eligible_attendance_segments',t.eligible_attendance_segments,'revision',t.revision) order by t.display_order,t.id) from reservations.booking_types t where t.event_id=e.id and t.scope_partition_id=e.scope_partition_id and t.active),'[]'::jsonb)) order by e.start_date desc,e.id),'[]'::jsonb)
 from reservations.events e where e.status not in('closed','full') and ((v_conference_id is null and e.scope_type='standalone' and e.conference_id is null) or (v_conference_id is not null and e.scope_type='conference' and e.conference_id=v_conference_id)) and reservations_private.has_event_permission(v_actor,'reservations.booking.create',e.id));
end $$;
revoke all on function reservations_private.conference_context(uuid,uuid,text) from public,anon,authenticated,service_role;
revoke all on function reservations_private.resolve_event_scope(uuid,uuid,text) from public,anon,authenticated,service_role;
revoke all on function reservations_private.effective_capabilities(uuid,jsonb) from public,anon,authenticated,service_role;
revoke all on function reservations_private.booking_creation_context(uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function reservations_private.conference_context(uuid,uuid,text) to service_role;
grant execute on function reservations_private.resolve_event_scope(uuid,uuid,text) to service_role;
grant execute on function reservations_private.effective_capabilities(uuid,jsonb) to service_role;
grant execute on function reservations_private.booking_creation_context(uuid,jsonb) to service_role;
commit;
