begin;

do $$ begin
  if to_regclass('public.conferences') is null
     or to_regclass('public.conference_participation_operations') is null
     or to_regprocedure('public.get_conference_core(uuid,uuid)') is null
     or to_regprocedure('public.mutate_conference_core(uuid,uuid,bigint,text,date,date,text)') is null
     or to_regprocedure('platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)') is null then
    raise exception 'C1A1_CANONICAL_CONFERENCE_CORE_REQUIRED' using errcode='55000';
  end if;
end $$;

alter table public.conferences
  add column place text not null default '',
  add constraint conferences_place_check
    check(place=btrim(place) and char_length(place)<=500);
comment on column public.conferences.place is
'Canonical Conference place. Empty is the clean default; no legacy snapshot backfill is performed.';

alter table public.conference_participation_operations
  drop constraint conference_participation_operations_operation_check;
alter table public.conference_participation_operations
  add constraint conference_participation_operations_operation_check check(operation in(
    'create','create_with_person','set_status','set_guardian','delete',
    'transport_vehicle_create','transport_vehicle_update','transport_vehicle_delete',
    'transport_assignment_set','transport_assignment_remove','restaurant_mutation',
    'accommodation_pricing_mutation','air_conditioning_mutation','finance_mutation',
    'conference_core_mutation'
  ));

do $$ declare sig regprocedure:='public.get_conference_core(uuid,uuid)'::regprocedure; d text;
  marker text:='''name'',v_conference.name,'; replacement text:='''name'',v_conference.name,''place'',v_conference.place,';
begin
  d:=pg_get_functiondef(sig);
  if position(marker in d)=0 or position('''place'',v_conference.place' in d)<>0 then
    raise exception 'C1A1_CORE_READ_PRECONDITION_FAILED' using errcode='55000';
  end if;
  execute replace(d,marker,replacement);
end $$;

create function public.mutate_conference_core(
  p_actor_device_id uuid,p_operation_id uuid,p_conference_id uuid,
  p_expected_revision bigint,p_name text,p_place text,
  p_start_date date,p_end_date date,p_status text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare ctx jsonb; session_ctx jsonb; actor uuid; authz uuid;
  prior public.conference_participation_operations%rowtype;
  current_row public.conferences%rowtype; changed public.conferences%rowtype;
  req jsonb; result jsonb; schedule jsonb; clean_name text:=btrim(coalesce(p_name,''));
  clean_place text:=btrim(coalesce(p_place,'')); completed timestamptz;
begin
  if p_operation_id is null or p_conference_id is null or p_expected_revision is null
     or p_expected_revision<1 or clean_name='' or char_length(clean_name)>500
     or char_length(clean_place)>500 or p_start_date is null or p_end_date is null
     or p_end_date<p_start_date or p_status not in('active','completed') then
    raise exception 'CONFERENCE_CORE_ARGUMENT_INVALID' using errcode='22023';
  end if;
  session_ctx:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;
  actor:=(session_ctx->>'user_id')::uuid;
  if session_ctx->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH'
     or (session_ctx->>'device_id')::uuid is distinct from p_actor_device_id then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end if;
  authz:=platform_private.validated_phase1c_device_authorization(actor,p_actor_device_id);
  if authz is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  ctx:=public.require_effective_module_permission(p_actor_device_id,'conference',
    'conference.lifecycle.manage','conference',p_conference_id::text);
  if (ctx->>'actorUserId')::uuid is distinct from actor then
    raise exception 'ACTOR_DEVICE_OVERRIDE_DENIED' using errcode='42501';
  end if;
  req:=jsonb_build_object('conferenceId',p_conference_id,'expectedRevision',p_expected_revision,
    'name',clean_name,'place',clean_place,'startDate',p_start_date,
    'endDate',p_end_date,'status',p_status);
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into prior from public.conference_participation_operations
    where actor_user_id=actor and operation_id=p_operation_id;
  if found then
    if prior.operation<>'conference_core_mutation' or prior.request<>req then
      raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';
    end if;
    return prior.result;
  end if;
  select * into current_row from public.conferences where id=p_conference_id for update;
  if not found or current_row.deleted_at is not null then raise exception 'CONFERENCE_CORE_NOT_FOUND' using errcode='P0002'; end if;
  if current_row.revision<>p_expected_revision then raise exception 'CONFERENCE_CORE_REVISION_CONFLICT' using errcode='40001'; end if;
  if current_row.status='completed' then raise exception 'CONFERENCE_LIFECYCLE_TRANSITION_INVALID' using errcode='55000'; end if;
  completed:=case when p_status='completed' then statement_timestamp() else null end;
  update public.conferences c set name=clean_name,place=clean_place,start_date=p_start_date,
    end_date=p_end_date,status=p_status,completed_at=completed,revision=c.revision+1,
    updated_by=actor,updated_at=statement_timestamp() where c.id=p_conference_id returning c.* into changed;
  select coalesce(jsonb_agg(to_jsonb(day::date) order by day),'[]'::jsonb) into schedule
    from generate_series(p_start_date::timestamp,p_end_date::timestamp,interval '1 day') day;
  result:=jsonb_build_object('conferenceId',changed.id,'name',changed.name,'place',changed.place,
    'startDate',changed.start_date,'endDate',changed.end_date,'status',changed.status,
    'completedAt',changed.completed_at,'revision',changed.revision,'updatedAt',changed.updated_at,
    'updatedBy',changed.updated_by,'days',(changed.end_date-changed.start_date)+1,
    'nights',changed.end_date-changed.start_date,'schedule',schedule);
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at)
    values(actor,p_operation_id,'conference_core_mutation',req,result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,
    entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source)
  values(actor,authz,'platform','conference',case when p_status='completed' then 'conference.lifecycle.completed' else 'conference.core.updated' end,
    'conference',p_conference_id,'platform',jsonb_build_object('name',current_row.name,'place',current_row.place,
    'startDate',current_row.start_date,'endDate',current_row.end_date,'status',current_row.status,'revision',current_row.revision),
    jsonb_build_object('name',changed.name,'place',changed.place,'startDate',changed.start_date,
    'endDate',changed.end_date,'status',changed.status,'revision',changed.revision),
    jsonb_build_object('permissionKey','conference.lifecycle.manage','authoritySource',ctx->>'authoritySource','grantId',ctx->'grantId'),
    p_operation_id,'rpc');
  return result;
end $$;

revoke all on function public.mutate_conference_core(uuid,uuid,uuid,bigint,text,text,date,date,text)
  from public,anon,authenticated,service_role;

do $$ declare sig regprocedure:='platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)'::regprocedure;
  d text; old text:='elsif p_operation=''mutate_conference_core'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_conference_id'',''p_expected_revision'',''p_name'',''p_start_date'',''p_end_date'',''p_status'']); return public.mutate_conference_core(p_actor_device_id,(p_args->>''p_conference_id'')::uuid,(p_args->>''p_expected_revision'')::bigint,p_args->>''p_name'',(p_args->>''p_start_date'')::date,(p_args->>''p_end_date'')::date,p_args->>''p_status'');';
  fresh text:='elsif p_operation=''mutate_conference_core'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_conference_id'',''p_expected_revision'',''p_name'',''p_place'',''p_start_date'',''p_end_date'',''p_status'']); return public.mutate_conference_core(p_actor_device_id,(p_args->>''p_operation_id'')::uuid,(p_args->>''p_conference_id'')::uuid,(p_args->>''p_expected_revision'')::bigint,p_args->>''p_name'',p_args->>''p_place'',(p_args->>''p_start_date'')::date,(p_args->>''p_end_date'')::date,p_args->>''p_status'');';
begin d:=pg_get_functiondef(sig);if position(old in d)=0 then raise exception 'C1A1_CORE_ROUTE_PRECONDITION_FAILED' using errcode='55000';end if;execute replace(d,old,fresh);end $$;

comment on function public.mutate_conference_core(uuid,uuid,uuid,bigint,text,text,date,date,text) is
'Canonical Conference Core mutation with place, shared replay ledger, exact-Conference lifecycle.manage authorization, optimistic revision, and platform audit.';

commit;
