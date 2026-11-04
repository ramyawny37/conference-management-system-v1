-- Reports are a module-scoped permission. Event selection still constrains the
-- returned partition, but must not be presented to the permission catalog as
-- an event-scoped grant.
create or replace function reservations_private.resolve_event_scope(
  p_device_id uuid,p_event_id uuid,p_permission text
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_event reservations.events%rowtype; v_context jsonb; v_actor uuid;
begin
  select * into v_event from reservations.events where id=p_event_id;
  if not found then raise exception 'RESERVATIONS_EVENT_NOT_FOUND' using errcode='P0002'; end if;
  if p_permission='reservations.reports.view' then
    v_context:=public.require_effective_module_permission(
      p_device_id,'reservations',p_permission,null,null
    );
  else
    v_context:=public.require_effective_module_permission(
      p_device_id,'reservations',p_permission,'event',p_event_id::text
    );
  end if;
  v_actor:=(v_context->>'actorUserId')::uuid;
  if v_event.scope_type='conference' then
    if not exists(
      select 1 from public.conferences c
      join public.organizations o on o.id=c.organization_id and o.status='active'
      join public.organization_members om on om.organization_id=c.organization_id and om.user_id=v_actor
      where c.id=v_event.conference_id and c.organization_id=v_event.organization_id and c.deleted_at is null
    ) then raise exception 'RESERVATIONS_CONFERENCE_ACCESS_REQUIRED' using errcode='42501'; end if;
  elsif v_event.scope_type<>'standalone' then
    raise exception 'RESERVATIONS_SCOPE_TYPE_INVALID' using errcode='22023';
  end if;
  return v_context||jsonb_build_object(
    'scopeType',v_event.scope_type,'scopePartitionId',v_event.scope_partition_id,
    'eventId',v_event.id,'conferenceId',v_event.conference_id,
    'organizationId',case when v_event.scope_type='conference' then v_event.organization_id end
  );
end $$;

revoke all on function reservations_private.resolve_event_scope(uuid,uuid,text)
  from public,anon,authenticated,service_role;
grant execute on function reservations_private.resolve_event_scope(uuid,uuid,text)
  to postgres;
