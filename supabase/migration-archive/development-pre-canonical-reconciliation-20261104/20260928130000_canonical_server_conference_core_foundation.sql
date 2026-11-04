begin;

-- P3A extends the existing Conference root. It does not migrate section data,
-- snapshots, memberships, Organizations, Reservations, or Warehouse data.
lock table public.conferences in share row exclusive mode;

do $$
declare
  v_missing text[];
begin
  if to_regclass('public.conferences') is null
     or to_regclass('public.module_permission_catalog') is null
     or to_regclass('public.module_permission_grants') is null
     or to_regclass('platform.audit_events') is null
     or to_regprocedure('public.require_effective_module_permission(uuid,text,text,text,text)') is null
     or to_regprocedure('platform_private.validated_phase1c_device_authorization(uuid,uuid)') is null
     or to_regprocedure('platform_private.require_exact_jsonb_keys(jsonb,text[],text[])') is null
     or to_regprocedure('platform.execute_conference_device_operation_phase1c_core(uuid,uuid,bytea,text,jsonb)') is null then
    raise exception 'P3A_CANONICAL_PLATFORM_FOUNDATION_REQUIRED' using errcode='55000';
  end if;

  select array_agg(required.name order by required.name)
    into v_missing
  from (values
    ('id','uuid'),('name','text'),('owner_id','uuid'),
    ('organization_id','uuid'),('created_at','timestamp with time zone'),
    ('updated_at','timestamp with time zone'),('deleted_at','timestamp with time zone')
  ) required(name,data_type)
  where not exists(
    select 1 from information_schema.columns columns
    where columns.table_schema='public' and columns.table_name='conferences'
      and columns.column_name=required.name and columns.data_type=required.data_type
  );
  if v_missing is not null then
    raise exception 'P3A_CONFERENCE_ROOT_CONTRACT_MISMATCH: %',v_missing using errcode='55000';
  end if;

  if exists(
    select 1 from information_schema.columns columns
    where columns.table_schema='public' and columns.table_name='conferences'
      and columns.column_name in(
        'start_date','end_date','status','completed_at','revision','updated_by'
      )
  ) then
    raise exception 'P3A_CONFERENCE_CORE_COLUMNS_ALREADY_EXIST' using errcode='55000';
  end if;

  if not exists(
    select 1 from public.module_permission_catalog catalog
    where catalog.permission_key='conference.lifecycle.manage'
      and catalog.module_key='conference' and catalog.status='active'
      and catalog.allowed_scope_mode='resource'
      and catalog.allowed_resource_type='conference'
  ) or not exists(
    select 1 from public.module_permission_catalog catalog
    where catalog.permission_key='conference.lifecycle.create'
      and catalog.module_key='conference' and catalog.status='active'
      and catalog.allowed_scope_mode='module'
      and catalog.allowed_resource_type is null
  ) then
    raise exception 'P3A_CONFERENCE_PERMISSION_CONTRACT_REQUIRED' using errcode='55000';
  end if;
end $$;

alter table public.conferences
  add column start_date date null,
  add column end_date date null,
  add column status text not null default 'active',
  add column completed_at timestamptz null,
  add column revision bigint not null default 1,
  add column updated_by uuid null references platform.profiles(user_id) on delete set null,
  add constraint conferences_core_name_check
    check(name=btrim(name) and char_length(name) between 1 and 500),
  add constraint conferences_core_date_pair_check
    check((start_date is null and end_date is null)
      or (start_date is not null and end_date is not null)),
  add constraint conferences_core_date_order_check
    check(start_date is null or end_date>=start_date),
  add constraint conferences_core_status_check
    check(status in('active','completed')),
  add constraint conferences_core_completion_check
    check((status='active' and completed_at is null)
      or (status='completed' and completed_at is not null)),
  add constraint conferences_core_revision_check check(revision>=1);

comment on table public.conferences is
'Canonical server Conference root. Section content and legacy snapshot state remain outside this row.';
comment on column public.conferences.organization_id is
'Conference business classification/ownership linkage retained for current consumers; never canonical Conference authorization.';
comment on column public.conferences.start_date is
'Canonical inclusive Conference start date; nullable only for pre-P3A rows until first canonical core mutation.';
comment on column public.conferences.end_date is
'Canonical inclusive Conference end date; nullable only for pre-P3A rows until first canonical core mutation.';
comment on column public.conferences.status is
'Canonical Conference lifecycle state: active or completed.';
comment on column public.conferences.revision is
'Canonical optimistic-concurrency revision for Conference core mutations.';

create function public.mutate_conference_core(
  p_actor_device_id uuid,
  p_conference_id uuid,
  p_expected_revision bigint,
  p_name text,
  p_start_date date,
  p_end_date date,
  p_status text
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
  v_current public.conferences%rowtype;
  v_updated public.conferences%rowtype;
  v_name text:=btrim(coalesce(p_name,''));
  v_completed_at timestamptz;
  v_old_values jsonb;
  v_new_values jsonb;
  v_schedule jsonb;
begin
  if p_conference_id is null or p_expected_revision is null or p_expected_revision<1
     or v_name='' or char_length(v_name)>500
     or p_start_date is null or p_end_date is null or p_end_date<p_start_date
     or p_status not in('active','completed') then
    raise exception 'CONFERENCE_CORE_ARGUMENT_INVALID' using errcode='22023';
  end if;

  v_context:=public.require_effective_module_permission(
    p_actor_device_id,'conference','conference.lifecycle.manage',
    'conference',p_conference_id::text
  );
  v_actor:=(v_context->>'actorUserId')::uuid;
  v_device_authorization_id:=platform_private.validated_phase1c_device_authorization(
    v_actor,p_actor_device_id
  );
  if v_device_authorization_id is null then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end if;

  select conferences.* into v_current
  from public.conferences conferences
  where conferences.id=p_conference_id
  for update;
  if not found or v_current.deleted_at is not null then
    raise exception 'CONFERENCE_CORE_NOT_FOUND' using errcode='P0002';
  end if;
  if v_current.revision<>p_expected_revision then
    raise exception 'CONFERENCE_CORE_REVISION_CONFLICT' using errcode='40001';
  end if;
  if v_current.status='completed' then
    raise exception 'CONFERENCE_LIFECYCLE_TRANSITION_INVALID' using errcode='55000';
  end if;

  v_completed_at:=case when p_status='completed'
    then statement_timestamp() else null end;
  v_old_values:=jsonb_build_object(
    'name',v_current.name,'startDate',v_current.start_date,
    'endDate',v_current.end_date,'status',v_current.status,
    'completedAt',v_current.completed_at,'revision',v_current.revision
  );

  update public.conferences conferences
  set name=v_name,start_date=p_start_date,end_date=p_end_date,status=p_status,
      completed_at=v_completed_at,revision=conferences.revision+1,
      updated_by=v_actor,updated_at=statement_timestamp()
  where conferences.id=p_conference_id
  returning conferences.* into v_updated;

  v_new_values:=jsonb_build_object(
    'name',v_updated.name,'startDate',v_updated.start_date,
    'endDate',v_updated.end_date,'status',v_updated.status,
    'completedAt',v_updated.completed_at,'revision',v_updated.revision
  );
  insert into platform.audit_events(
    actor_user_id,actor_device_authorization_id,subject_user_id,
    domain,module,action,entity_type,entity_id,scope_type,scope_id,
    old_values,new_values,metadata,source
  ) values(
    v_actor,v_device_authorization_id,null,
    'platform','conference',
    case when p_status='completed'
      then 'conference.lifecycle.completed' else 'conference.core.updated' end,
    'conference',p_conference_id,'platform',null,
    v_old_values,v_new_values,
    jsonb_build_object(
      'permissionKey','conference.lifecycle.manage',
      'authoritySource',v_context->>'authoritySource',
      'grantId',v_context->'grantId'
    ),'rpc'
  );

  select coalesce(jsonb_agg(to_jsonb(schedule_day::date)
    order by schedule_day),'[]'::jsonb)
    into v_schedule
  from generate_series(
    p_start_date::timestamp,p_end_date::timestamp,interval '1 day'
  ) schedule_day;

  return jsonb_build_object(
    'conferenceId',v_updated.id,'name',v_updated.name,
    'startDate',v_updated.start_date,'endDate',v_updated.end_date,
    'status',v_updated.status,'completedAt',v_updated.completed_at,
    'revision',v_updated.revision,'updatedAt',v_updated.updated_at,
    'updatedBy',v_updated.updated_by,
    'days',(v_updated.end_date-v_updated.start_date)+1,
    'nights',v_updated.end_date-v_updated.start_date,
    'schedule',v_schedule
  );
end $$;

revoke all on function public.mutate_conference_core(
  uuid,uuid,bigint,text,date,date,text
) from public,anon,authenticated,service_role;

-- Add one isolated operation to the existing verified Conference session
-- dispatcher. All legacy cases and their authorization remain unchanged.
do $$
declare
  v_signature regprocedure:=
    'platform.execute_conference_device_operation_phase1c_core(uuid,uuid,bytea,text,jsonb)'::regprocedure;
  v_definition text;
  v_marker text:='else raise exception ''CONFERENCE_OPERATION_NOT_ALLOWED'' using errcode=''42501'';';
  v_branch text:='when ''mutate_conference_core'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_conference_id'',''p_expected_revision'',''p_name'',''p_start_date'',''p_end_date'',''p_status'']); v_result:=public.mutate_conference_core(v_session.device_id,(p_args->>''p_conference_id'')::uuid,(p_args->>''p_expected_revision'')::bigint,p_args->>''p_name'',(p_args->>''p_start_date'')::date,(p_args->>''p_end_date'')::date,p_args->>''p_status''); ';
  v_occurrences integer;
begin
  v_definition:=pg_get_functiondef(v_signature);
  if position('when ''mutate_conference_core'' then' in v_definition)<>0 then
    raise exception 'P3A_CONFERENCE_CORE_DISPATCH_ALREADY_EXISTS' using errcode='55000';
  end if;
  v_occurrences:=(length(v_definition)-length(replace(v_definition,v_marker,'')))
    / length(v_marker);
  if v_occurrences<>1 then
    raise exception 'P3A_CONFERENCE_DISPATCH_PRECONDITION_FAILED' using errcode='55000';
  end if;
  execute replace(v_definition,v_marker,v_branch||v_marker);
  v_definition:=pg_get_functiondef(v_signature);
  if position('when ''mutate_conference_core'' then' in v_definition)=0
     or position('public.mutate_conference_core(v_session.device_id' in v_definition)=0
     or position('p_actor_user_id' in v_branch)<>0
     or position('p_actor_device_id' in v_branch)<>0 then
    raise exception 'P3A_CONFERENCE_DISPATCH_POSTCONDITION_FAILED' using errcode='55000';
  end if;
end $$;

comment on function public.mutate_conference_core(
  uuid,uuid,bigint,text,date,date,text
) is
'P3A canonical Conference-core mutation. Actor/device come from the verified Platform session; authority is exact-Conference conference.lifecycle.manage; dates derive days/nights/schedule; revision rejects stale writes.';

commit;
