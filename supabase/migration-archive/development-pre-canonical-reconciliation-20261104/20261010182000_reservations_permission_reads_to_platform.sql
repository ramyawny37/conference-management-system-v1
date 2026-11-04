begin;

create or replace function reservations_private.has_event_permission(
  p_actor uuid,p_permission text,p_event_id uuid
) returns boolean language sql stable security definer set search_path='' as $$
  select platform_private.is_canonical_platform_owner(p_actor) or exists(
    select 1
    from platform.permission_grants grant_row
    join platform.permissions permission on permission.id=grant_row.permission_id
    where grant_row.user_id=p_actor and permission.domain='reservations'
      and permission.code=p_permission and permission.status='active'
      and grant_row.revoked_at is null
      and (
        grant_row.scope_type='module'
        or (grant_row.scope_type='resource' and grant_row.resource_type='event'
            and grant_row.resource_id=p_event_id::text)
      )
  )
$$;

create or replace function reservations_private.effective_capabilities(
  p_device_id uuid,p_args jsonb
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid;v_conference_id uuid;v_is_owner boolean;
begin
  if p_args is null or jsonb_typeof(p_args)<>'object' then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
  v_actor:=public.require_current_approved_device(p_device_id);
  v_is_owner:=platform_private.is_canonical_platform_owner(v_actor);
  if p_args ? 'p_conference_id' and not p_args ? 'p_scope_type' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    v_conference_id:=nullif(p_args->>'p_conference_id','')::uuid;
    if v_conference_id is null or not exists(
      select 1 from public.conferences c
      join public.organizations o on o.id=c.organization_id and o.status='active'
      join public.organization_members om on om.organization_id=c.organization_id and om.user_id=v_actor
      where c.id=v_conference_id and c.deleted_at is null
    ) then raise exception 'RESERVATIONS_CONFERENCE_ACCESS_REQUIRED' using errcode='42501'; end if;
  elsif p_args ? 'p_scope_type' and not p_args ? 'p_conference_id' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_scope_type']);
    if p_args->>'p_scope_type'<>'standalone' then raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
  else raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;
  return jsonb_build_object('permissions',coalesce((
    select jsonb_agg(x.permission_key order by x.permission_key) from (
      select permission.code permission_key
      from platform.permissions permission
      where v_is_owner and permission.domain='reservations' and permission.status='active'
      union
      select permission.code
      from platform.permission_grants grant_row
      join platform.permissions permission on permission.id=grant_row.permission_id
      where grant_row.user_id=v_actor and permission.domain='reservations'
        and permission.status='active' and grant_row.revoked_at is null
        and (
          grant_row.scope_type='module'
          or (
            grant_row.scope_type='resource' and grant_row.resource_type='event'
            and exists(
              select 1 from reservations.events e
              where e.id::text=grant_row.resource_id
                and ((v_conference_id is null and e.scope_type='standalone' and e.conference_id is null and e.organization_id is null)
                  or (v_conference_id is not null and e.scope_type='conference' and e.conference_id=v_conference_id))
            )
          )
        )
    ) x
  ),'[]'::jsonb));
end $$;

revoke all on function reservations_private.has_event_permission(uuid,text,uuid) from public,anon,authenticated,service_role;
revoke all on function reservations_private.effective_capabilities(uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function reservations_private.has_event_permission(uuid,text,uuid) to service_role;
grant execute on function reservations_private.effective_capabilities(uuid,jsonb) to service_role;

commit;