-- Canonical Reservations capability projection for navigation and route gating.
-- Advisory UI state only; every operation remains server-authorized.
create function reservations_private.effective_capabilities(p_device_id uuid,p_args jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid; v_conference_id uuid; v_is_owner boolean;
begin
  if p_args is null or jsonb_typeof(p_args)<>'object' then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
  v_actor:=public.require_current_approved_device(p_device_id);
  v_is_owner:=public.is_system_owner(v_actor);
  if p_args ? 'p_conference_id' and not p_args ? 'p_scope_type' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    v_conference_id:=nullif(p_args->>'p_conference_id','')::uuid;
    if v_conference_id is null or not exists(select 1 from public.conferences c join public.organizations o on o.id=c.organization_id and o.status='active' join public.organization_members om on om.organization_id=c.organization_id and om.user_id=v_actor where c.id=v_conference_id and c.deleted_at is null) then raise exception 'RESERVATIONS_CONFERENCE_ACCESS_REQUIRED' using errcode='42501'; end if;
  elsif p_args ? 'p_scope_type' and not p_args ? 'p_conference_id' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_scope_type']);
    if p_args->>'p_scope_type'<>'standalone' then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
  else raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
  return jsonb_build_object('permissions',coalesce((
    select jsonb_agg(x.permission_key order by x.permission_key) from (
      select p.permission_key from public.module_permission_catalog p where v_is_owner and p.module_key='reservations' and p.status='active'
      union
      select g.permission_key from public.module_permission_grants g
      where g.user_id=v_actor and g.module_key='reservations' and g.revoked_at is null and (
        (g.resource_type is null and g.resource_id is null) or
        (g.resource_type='event' and exists(select 1 from reservations.events e where e.id::text=g.resource_id and ((v_conference_id is null and e.scope_type='standalone' and e.conference_id is null and e.organization_id is null) or (v_conference_id is not null and e.scope_type='conference' and e.conference_id=v_conference_id))))
      )
    ) x
  ),'[]'::jsonb));
end $$;
revoke all on function reservations_private.effective_capabilities(uuid,jsonb) from public,anon,authenticated,service_role;
alter function reservations.read(uuid,text,jsonb) rename to read_pre_effective_capability_contract;
create function reservations.read(p_device_id uuid,p_operation text,p_args jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if p_operation='get_effective_capabilities' then return reservations_private.effective_capabilities(p_device_id,p_args); end if;
  return reservations.read_pre_effective_capability_contract(p_device_id,p_operation,p_args);
end $$;
revoke all on function reservations.read(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function reservations.read(uuid,text,jsonb) to service_role;
