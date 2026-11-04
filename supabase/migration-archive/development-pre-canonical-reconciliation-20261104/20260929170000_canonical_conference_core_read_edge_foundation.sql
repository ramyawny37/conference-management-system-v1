begin;

do $$
begin
  if to_regclass('public.conferences') is null
     or to_regprocedure('public.require_effective_module_permission(uuid,text,text,text,text)') is null
     or to_regprocedure('platform_private.validated_phase1c_device_authorization(uuid,uuid)') is null
     or to_regprocedure('platform_private.require_exact_jsonb_keys(jsonb,text[],text[])') is null
     or to_regprocedure('platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)') is null then
    raise exception 'P6B0_CANONICAL_CONFERENCE_FOUNDATION_REQUIRED' using errcode='55000';
  end if;
  if not exists(
    select 1 from public.module_permission_catalog catalog
    where catalog.permission_key='conference.access.view'
      and catalog.module_key='conference' and catalog.status='active'
      and catalog.allowed_scope_mode='resource'
      and catalog.allowed_resource_type='conference'
  ) then
    raise exception 'P6B0_CONFERENCE_VIEW_PERMISSION_REQUIRED' using errcode='55000';
  end if;
end $$;

create function public.get_conference_core(
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
    'organizationId',v_conference.organization_id,
    'name',v_conference.name,
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

revoke all on function public.get_conference_core(uuid,uuid)
  from public,anon,authenticated,service_role;

do $$
declare
  v_signature regprocedure:=
    'platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)'::regprocedure;
  v_definition text;
  v_marker text:='if p_operation=''get_conference_accommodation'' then';
  v_branch text:='if p_operation=''get_conference_core'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_conference_id'']); return public.get_conference_core(p_actor_device_id,(p_args->>''p_conference_id'')::uuid); elsif p_operation=''get_conference_accommodation'' then';
  v_occurrences integer;
begin
  v_definition:=pg_get_functiondef(v_signature);
  if position('p_operation=''get_conference_core''' in v_definition)<>0 then
    raise exception 'P6B0_CONFERENCE_CORE_READ_ROUTE_ALREADY_EXISTS' using errcode='55000';
  end if;
  v_occurrences:=(length(v_definition)-length(replace(v_definition,v_marker,'')))
    / length(v_marker);
  if v_occurrences<>1 then
    raise exception 'P6B0_CANONICAL_ROUTER_PRECONDITION_FAILED' using errcode='55000';
  end if;
  execute replace(v_definition,v_marker,v_branch);
  v_definition:=pg_get_functiondef(v_signature);
  if position('p_operation=''get_conference_core''' in v_definition)=0
     or position('public.get_conference_core(p_actor_device_id' in v_definition)=0 then
    raise exception 'P6B0_CANONICAL_ROUTER_POSTCONDITION_FAILED' using errcode='55000';
  end if;
end $$;

comment on function public.get_conference_core(uuid,uuid) is
'Canonical Conference-core read through the validated Platform device-session router. Exact-Conference conference.access.view authority is required; duration and schedule are derived from canonical dates.';

commit;
