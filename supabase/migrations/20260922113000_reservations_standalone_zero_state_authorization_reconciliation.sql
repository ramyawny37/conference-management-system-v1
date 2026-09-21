begin;

-- Standalone Reservations must initialize through the same canonical module
-- authority used by mutations. In particular, a system owner with an approved
-- device must be able to reach an empty standalone event state without a
-- synthetic module grant or seed event.
create or replace function reservations_private.booking_creation_context(
  p_device_id uuid,
  p_args jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_context jsonb;
  v_actor uuid;
  v_conference_id uuid;
begin
  if p_args is null or jsonb_typeof(p_args)<>'object' then
    raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023';
  end if;

  if p_args ? 'p_conference_id' and not p_args ? 'p_scope_type' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    v_conference_id:=nullif(p_args->>'p_conference_id','')::uuid;
    if v_conference_id is null then
      raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023';
    end if;

    -- Authorize the read before discovering targets. booking.create is the
    -- minimum permission needed by this context and system-owner authority is
    -- resolved by require_effective_module_permission itself.
    v_context:=public.require_effective_module_permission(
      p_device_id,'reservations','reservations.booking.create',null,null
    );
    v_actor:=(v_context->>'actorUserId')::uuid;

    if not exists(
      select 1
      from public.conferences c
      join public.organizations o
        on o.id=c.organization_id and o.status='active'
      join public.organization_members om
        on om.organization_id=c.organization_id and om.user_id=v_actor
      where c.id=v_conference_id and c.deleted_at is null
    ) then
      raise exception 'RESERVATIONS_CONFERENCE_ACCESS_REQUIRED' using errcode='42501';
    end if;
  elsif p_args ? 'p_scope_type' and not p_args ? 'p_conference_id' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_scope_type']);
    if p_args->>'p_scope_type'<>'standalone' then
      raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023';
    end if;

    v_context:=public.require_effective_module_permission(
      p_device_id,'reservations','reservations.booking.create',null,null
    );
    v_actor:=(v_context->>'actorUserId')::uuid;
  else
    raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023';
  end if;

  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',e.id,
      'conference_id',e.conference_id,
      'name',e.name,
      'start_date',e.start_date,
      'end_date',e.end_date,
      'location',e.location,
      'capacity',e.capacity,
      'status',e.status,
      'notes','',
      'revision',e.revision,
      'bookingTypes',coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',t.id,
          'event_id',t.event_id,
          'name',t.name,
          'code',t.code,
          'price',t.price,
          'active',t.active,
          'display_order',t.display_order,
          'eligible_attendance_segments',t.eligible_attendance_segments,
          'revision',t.revision
        ) order by t.display_order,t.id)
        from reservations.booking_types t
        where t.event_id=e.id
          and t.scope_partition_id=e.scope_partition_id
          and t.active
      ),'[]'::jsonb)
    ) order by e.start_date desc,e.id),'[]'::jsonb)
    from reservations.events e
    where e.status not in('closed','full')
      and (
        (v_conference_id is null
          and e.scope_type='standalone'
          and e.conference_id is null
          and e.organization_id is null)
        or
        (v_conference_id is not null
          and e.scope_type='conference'
          and e.conference_id=v_conference_id)
      )
      and reservations_private.has_event_permission(
        v_actor,'reservations.booking.create',e.id
      )
  );
end $$;

revoke all on function reservations_private.booking_creation_context(uuid,jsonb)
from public,anon,authenticated,service_role;
grant execute on function reservations_private.booking_creation_context(uuid,jsonb)
to postgres;

commit;
