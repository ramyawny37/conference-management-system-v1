begin;

do $$ begin
  if to_regclass('platform.people') is null
     or to_regclass('public.conference_participations') is null
     or to_regclass('public.conference_participation_operations') is null
     or to_regprocedure('platform_private.require_conference_participation_context(uuid,uuid,text,boolean)') is null
     or to_regprocedure('platform_private.validated_phase1c_device_authorization(uuid,uuid)') is null
     or to_regprocedure('platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)') is null then
    raise exception 'P6C_B1_CANONICAL_PARTICIPATION_FOUNDATION_REQUIRED' using errcode='55000';
  end if;
end $$;

create or replace function public.list_conference_participations(p_actor_device_id uuid,p_conference_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_context jsonb; v_items jsonb; v_total bigint; v_active bigint; v_apologized bigint;
begin
  v_context:=platform_private.require_conference_participation_context(p_actor_device_id,p_conference_id,'conference.people.view',false);
  select count(*),count(*) filter(where participation.status='active'),count(*) filter(where participation.status='apologized'),
    coalesce(jsonb_agg(jsonb_build_object('participationId',participation.id,'conferenceId',participation.conference_id,
      'personId',participation.person_id,'status',participation.status,'revision',participation.revision,
      'createdAt',participation.created_at,'updatedAt',participation.updated_at,'createdBy',participation.created_by,
      'updatedBy',participation.updated_by,'person',jsonb_build_object('personId',person.id,
        'fullName',person.full_name,'phone',person.phone,'gender',person.gender,
        'dateOfBirth',person.date_of_birth,'church',person.church))
      order by participation.created_at,participation.id),'[]'::jsonb)
  into v_total,v_active,v_apologized,v_items
  from public.conference_participations participation join platform.people person on person.id=participation.person_id
  where participation.conference_id=p_conference_id;
  return jsonb_build_object('conferenceId',p_conference_id,'totalCount',v_total,'activeCount',v_active,
    'apologizedCount',v_apologized,'items',v_items);
end $$;

alter table public.conference_participation_operations drop constraint conference_participation_operations_operation_check;
alter table public.conference_participation_operations add constraint conference_participation_operations_operation_check
  check(operation in('create','create_with_person','set_status','delete'));

create function public.create_conference_participation_with_person(
  p_actor_device_id uuid,p_operation_id uuid,p_conference_id uuid,p_full_name text,
  p_phone text,p_gender text,p_date_of_birth date,p_church text
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_context jsonb; v_actor uuid; v_device_authorization uuid; v_request jsonb;
  v_prior public.conference_participation_operations%rowtype; v_person platform.people%rowtype;
  v_participation public.conference_participations%rowtype; v_person_projection jsonb; v_result jsonb;
begin
  if p_operation_id is null or p_conference_id is null or p_full_name is null or btrim(p_full_name)=''
     or length(btrim(p_full_name))>240
     or (p_phone is not null and (btrim(p_phone)='' or length(btrim(p_phone))>40))
     or (p_gender is not null and p_gender not in('male','female'))
     or (p_church is not null and (btrim(p_church)='' or length(btrim(p_church))>200)) then
    raise exception 'CONFERENCE_PARTICIPANT_PERSON_ARGUMENT_INVALID' using errcode='22023';
  end if;
  v_context:=platform_private.require_conference_participation_context(p_actor_device_id,p_conference_id,'conference.people.manage',true);
  v_actor:=(v_context->>'actorUserId')::uuid;
  v_device_authorization:=platform_private.validated_phase1c_device_authorization(v_actor,p_actor_device_id);
  if v_device_authorization is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  v_request:=jsonb_build_object('conferenceId',p_conference_id,'fullName',btrim(p_full_name),
    'phone',case when p_phone is null then null else btrim(p_phone) end,'gender',p_gender,
    'dateOfBirth',p_date_of_birth,'church',case when p_church is null then null else btrim(p_church) end);
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into v_prior from public.conference_participation_operations where actor_user_id=v_actor and operation_id=p_operation_id;
  if found then
    if v_prior.operation<>'create_with_person' or v_prior.request<>v_request then
      raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';
    end if;
    return v_prior.result;
  end if;
  insert into platform.people(full_name,phone,gender,date_of_birth,church,created_by,updated_by)
  values(btrim(p_full_name),case when p_phone is null then null else btrim(p_phone) end,p_gender,p_date_of_birth,
    case when p_church is null then null else btrim(p_church) end,v_actor,v_actor) returning * into v_person;
  insert into public.conference_participations(conference_id,person_id,created_by,updated_by)
  values(p_conference_id,v_person.id,v_actor,v_actor) returning * into v_participation;
  v_person_projection:=jsonb_build_object('personId',v_person.id,'fullName',v_person.full_name,'phone',v_person.phone,
    'gender',v_person.gender,'dateOfBirth',v_person.date_of_birth,'church',v_person.church);
  v_result:=jsonb_build_object('participationId',v_participation.id,'conferenceId',v_participation.conference_id,
    'personId',v_participation.person_id,'status',v_participation.status,'revision',v_participation.revision,
    'createdAt',v_participation.created_at,'updatedAt',v_participation.updated_at,'createdBy',v_participation.created_by,
    'updatedBy',v_participation.updated_by,'person',v_person_projection);
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at)
  values(v_actor,p_operation_id,'create_with_person',v_request,v_result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,
    entity_id,scope_type,new_values,metadata,operation_id,source)
  values(v_actor,v_device_authorization,'platform','conference','platform.person.created','person',v_person.id,
      'platform',v_person_projection,jsonb_build_object('conferenceId',p_conference_id,'participationId',v_participation.id,
        'permissionKey','conference.people.manage','authoritySource',v_context->>'authoritySource','grantId',v_context->'grantId'),p_operation_id,'rpc'),
    (v_actor,v_device_authorization,'platform','conference','conference.participation.created','conference_participation',
      v_participation.id,'platform',v_result,jsonb_build_object('conferenceId',p_conference_id,'personId',v_person.id,
        'permissionKey','conference.people.manage','authoritySource',v_context->>'authoritySource','grantId',v_context->'grantId'),p_operation_id,'rpc');
  return v_result;
end $$;

revoke all on function public.list_conference_participations(uuid,uuid),
  public.create_conference_participation_with_person(uuid,uuid,uuid,text,text,text,date,text)
  from public,anon,authenticated,service_role;

do $$
declare v_signature regprocedure:='platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)'::regprocedure;
  v_definition text; v_marker text:='elsif p_operation=''list_conference_participations'' then';
  v_branch text:='elsif p_operation=''create_conference_participation_with_person'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_conference_id'',''p_full_name'',''p_phone'',''p_gender'',''p_date_of_birth'',''p_church'']); return public.create_conference_participation_with_person(p_actor_device_id,(p_args->>''p_operation_id'')::uuid,(p_args->>''p_conference_id'')::uuid,p_args->>''p_full_name'',p_args->>''p_phone'',p_args->>''p_gender'',(p_args->>''p_date_of_birth'')::date,p_args->>''p_church''); elsif p_operation=''list_conference_participations'' then';
  v_occurrences integer;
begin
  v_definition:=pg_get_functiondef(v_signature);
  if position('p_operation=''create_conference_participation_with_person''' in v_definition)<>0 then
    raise exception 'P6C_B1_PARTICIPANT_CREATE_ROUTE_ALREADY_EXISTS' using errcode='55000';
  end if;
  v_occurrences:=(length(v_definition)-length(replace(v_definition,v_marker,'')))/length(v_marker);
  if v_occurrences<>1 then raise exception 'P6C_B1_CANONICAL_ROUTER_PRECONDITION_FAILED' using errcode='55000'; end if;
  execute replace(v_definition,v_marker,v_branch);
  if position('p_operation=''create_conference_participation_with_person''' in pg_get_functiondef(v_signature))=0 then
    raise exception 'P6C_B1_CANONICAL_ROUTER_POSTCONDITION_FAILED' using errcode='55000';
  end if;
end $$;

comment on function public.create_conference_participation_with_person(uuid,uuid,uuid,text,text,text,date,text)
is 'Conference-scoped atomic creation of one canonical Platform Person and its Participation through the protected device-session dispatcher; not a generic Person Bank API.';

commit;
