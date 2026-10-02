begin;

do $$ begin
  if to_regprocedure('platform_private.require_conference_accommodation_context(uuid,uuid,text,boolean)') is null
     or to_regprocedure('platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)') is null
     or to_regclass('public.conference_accommodation_houses') is null then
    raise exception 'P6I_B4A_BASELINE_REQUIRED' using errcode='55000';
  end if;
end $$;

create table public.conference_accommodation_pricing(
  conference_id uuid primary key references public.conferences(id) on delete cascade,
  enabled boolean not null default true,
  pricing_mode text not null default 'per_person_night' check(pricing_mode in('per_person_night','per_room_night','per_person_day','per_room_day','fixed_package','per_day_package','room_type')),
  person_night numeric(14,2) not null default 0 check(person_night>=0),
  room_night numeric(14,2) not null default 0 check(room_night>=0),
  person_day numeric(14,2) not null default 0 check(person_day>=0),
  room_day numeric(14,2) not null default 0 check(room_day>=0),
  package_price numeric(14,2) not null default 0 check(package_price>=0),
  package_day_price numeric(14,2) not null default 0 check(package_day_price>=0),
  single_price numeric(14,2) not null default 0 check(single_price>=0),
  double_price numeric(14,2) not null default 0 check(double_price>=0),
  triple_price numeric(14,2) not null default 0 check(triple_price>=0),
  quadruple_price numeric(14,2) not null default 0 check(quadruple_price>=0),
  quintuple_price numeric(14,2) not null default 0 check(quintuple_price>=0),
  sextuple_price numeric(14,2) not null default 0 check(sextuple_price>=0),
  seven_plus_price numeric(14,2) not null default 0 check(seven_plus_price>=0),
  revision bigint not null default 1 check(revision>=1),
  created_at timestamptz not null default statement_timestamp(),
  created_by uuid not null references platform.profiles(user_id),
  updated_at timestamptz not null default statement_timestamp(),
  updated_by uuid not null references platform.profiles(user_id)
);
alter table public.conference_accommodation_pricing enable row level security;
alter table public.conference_accommodation_pricing force row level security;
revoke all on table public.conference_accommodation_pricing from public,anon,authenticated,service_role;

alter table public.conference_participation_operations drop constraint conference_participation_operations_operation_check;
alter table public.conference_participation_operations add constraint conference_participation_operations_operation_check check(operation in('create','create_with_person','set_status','set_guardian','delete','transport_vehicle_create','transport_vehicle_update','transport_vehicle_delete','transport_assignment_set','transport_assignment_remove','restaurant_mutation','accommodation_pricing_mutation'));

create function platform_private.conference_accommodation_pricing_projection(p_conference uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'enabled',coalesce(s.enabled,true),'pricingMode',coalesce(s.pricing_mode,'per_person_night'),
    'prices',jsonb_build_object('personNight',coalesce(s.person_night,0),'roomNight',coalesce(s.room_night,0),'personDay',coalesce(s.person_day,0),'roomDay',coalesce(s.room_day,0),'packagePrice',coalesce(s.package_price,0),'packageDayPrice',coalesce(s.package_day_price,0)),
    'roomTypePrices',jsonb_build_object('single',coalesce(s.single_price,0),'double',coalesce(s.double_price,0),'triple',coalesce(s.triple_price,0),'quadruple',coalesce(s.quadruple_price,0),'quintuple',coalesce(s.quintuple_price,0),'sextuple',coalesce(s.sextuple_price,0),'sevenPlus',coalesce(s.seven_plus_price,0)),
    'revision',coalesce(s.revision,0),'updatedAt',s.updated_at,'updatedBy',s.updated_by)
  from (select p_conference conference_id) c left join public.conference_accommodation_pricing s using(conference_id)
$$;

do $$ declare sig regprocedure:='public.get_conference_accommodation(uuid,uuid)'::regprocedure; d text; marker text:='return jsonb_build_object(''conferenceId'',p_conference,''houses'',result);'; replacement text:='return jsonb_build_object(''conferenceId'',p_conference,''houses'',result,''pricing'',platform_private.conference_accommodation_pricing_projection(p_conference));'; begin
  d:=pg_get_functiondef(sig); if position(marker in d)=0 then raise exception 'P6I_B4A_READ_PRECONDITION_FAILED' using errcode='55000'; end if; execute replace(d,marker,replacement);
end $$;
comment on function public.get_conference_accommodation(uuid,uuid) is 'Canonical Accommodation projection; existing conference.accommodation.view authorization is preserved.';

create function public.mutate_conference_accommodation_pricing(p_actor_device_id uuid,p_operation_id uuid,p_conference_id uuid,p_expected_revision bigint,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare ctx jsonb; session_ctx jsonb; actor uuid; authz uuid; prior public.conference_participation_operations%rowtype; current_row public.conference_accommodation_pricing%rowtype; changed public.conference_accommodation_pricing%rowtype; req jsonb; result jsonb; mode text; vals numeric[];
begin
  if p_operation_id is null or p_conference_id is null or jsonb_typeof(p_payload)<>'object' then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ARGUMENT_INVALID' using errcode='22023'; end if;
  perform platform_private.require_exact_jsonb_keys(p_payload,array['enabled','pricingMode','prices','roomTypePrices']);
  perform platform_private.require_exact_jsonb_keys(p_payload->'prices',array['personNight','roomNight','personDay','roomDay','packagePrice','packageDayPrice']);
  perform platform_private.require_exact_jsonb_keys(p_payload->'roomTypePrices',array['single','double','triple','quadruple','quintuple','sextuple','sevenPlus']);
  mode:=p_payload->>'pricingMode'; if mode not in('per_person_night','per_room_night','per_person_day','per_room_day','fixed_package','per_day_package','room_type') then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ARGUMENT_INVALID' using errcode='22023'; end if;
  begin vals:=array[(p_payload->'prices'->>'personNight')::numeric,(p_payload->'prices'->>'roomNight')::numeric,(p_payload->'prices'->>'personDay')::numeric,(p_payload->'prices'->>'roomDay')::numeric,(p_payload->'prices'->>'packagePrice')::numeric,(p_payload->'prices'->>'packageDayPrice')::numeric,(p_payload->'roomTypePrices'->>'single')::numeric,(p_payload->'roomTypePrices'->>'double')::numeric,(p_payload->'roomTypePrices'->>'triple')::numeric,(p_payload->'roomTypePrices'->>'quadruple')::numeric,(p_payload->'roomTypePrices'->>'quintuple')::numeric,(p_payload->'roomTypePrices'->>'sextuple')::numeric,(p_payload->'roomTypePrices'->>'sevenPlus')::numeric]; exception when others then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ARGUMENT_INVALID' using errcode='22023'; end;
  if exists(select 1 from unnest(vals) v where v<0) then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ARGUMENT_INVALID' using errcode='22023'; end if;
  session_ctx:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb; actor:=(session_ctx->>'user_id')::uuid;
  if session_ctx->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or (session_ctx->>'device_id')::uuid is distinct from p_actor_device_id then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  authz:=platform_private.validated_phase1c_device_authorization(actor,p_actor_device_id); if authz is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  ctx:=platform_private.require_conference_accommodation_context(p_actor_device_id,p_conference_id,'conference.accommodation.manage',true);
  req:=jsonb_build_object('conferenceId',p_conference_id,'expectedRevision',p_expected_revision,'payload',p_payload);
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':conference-participation:'||p_operation_id::text,0)); select * into prior from public.conference_participation_operations where actor_user_id=actor and operation_id=p_operation_id;
  if found then if prior.operation<>'accommodation_pricing_mutation' or prior.request<>req then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023'; end if; return prior.result; end if;
  perform pg_advisory_xact_lock(hashtextextended('conference-accommodation-pricing:'||p_conference_id::text,0)); select * into current_row from public.conference_accommodation_pricing where conference_id=p_conference_id for update;
  if found and (p_expected_revision is null or current_row.revision<>p_expected_revision) then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_REVISION_CONFLICT' using errcode='40001'; end if;
  if not found and p_expected_revision is not null and p_expected_revision<>0 then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_REVISION_CONFLICT' using errcode='40001'; end if;
  insert into public.conference_accommodation_pricing(conference_id,enabled,pricing_mode,person_night,room_night,person_day,room_day,package_price,package_day_price,single_price,double_price,triple_price,quadruple_price,quintuple_price,sextuple_price,seven_plus_price,revision,created_by,updated_by)
  values(p_conference_id,(p_payload->>'enabled')::boolean,mode,vals[1],vals[2],vals[3],vals[4],vals[5],vals[6],vals[7],vals[8],vals[9],vals[10],vals[11],vals[12],vals[13],1,actor,actor)
  on conflict(conference_id) do update set enabled=excluded.enabled,pricing_mode=excluded.pricing_mode,person_night=excluded.person_night,room_night=excluded.room_night,person_day=excluded.person_day,room_day=excluded.room_day,package_price=excluded.package_price,package_day_price=excluded.package_day_price,single_price=excluded.single_price,double_price=excluded.double_price,triple_price=excluded.triple_price,quadruple_price=excluded.quadruple_price,quintuple_price=excluded.quintuple_price,sextuple_price=excluded.sextuple_price,seven_plus_price=excluded.seven_plus_price,revision=public.conference_accommodation_pricing.revision+1,updated_at=statement_timestamp(),updated_by=actor returning * into changed;
  result:=jsonb_build_object('conferenceId',p_conference_id,'pricing',platform_private.conference_accommodation_pricing_projection(p_conference_id));
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at) values(actor,p_operation_id,'accommodation_pricing_mutation',req,result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source) values(actor,authz,'platform','conference','conference.accommodation.pricing_updated','conference_accommodation_pricing',p_conference_id,'platform',case when current_row.conference_id is null then null else to_jsonb(current_row) end,to_jsonb(changed),jsonb_build_object('conferenceId',p_conference_id,'permissionKey','conference.accommodation.manage','authoritySource',ctx->>'authoritySource','grantId',ctx->'grantId'),p_operation_id,'rpc');
  return result;
exception when invalid_text_representation or null_value_not_allowed then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ARGUMENT_INVALID' using errcode='22023';
end $$;

revoke all on function platform_private.conference_accommodation_pricing_projection(uuid),public.mutate_conference_accommodation_pricing(uuid,uuid,uuid,bigint,jsonb),public.get_conference_accommodation(uuid,uuid) from public,anon,authenticated,service_role;
do $$ declare sig regprocedure:='platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)'::regprocedure; d text; marker text:='if p_operation=''get_conference_restaurant'' then'; branch text:='if p_operation=''mutate_conference_accommodation_pricing'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_conference_id'',''p_expected_revision'',''p_payload'']);return public.mutate_conference_accommodation_pricing(p_actor_device_id,(p_args->>''p_operation_id'')::uuid,(p_args->>''p_conference_id'')::uuid,nullif(p_args->>''p_expected_revision'','''')::bigint,p_args->''p_payload'');elsif p_operation=''get_conference_restaurant'' then'; begin d:=pg_get_functiondef(sig);if position(marker in d)=0 then raise exception 'P6I_B4A_ROUTER_PRECONDITION_FAILED' using errcode='55000';end if;execute replace(d,marker,branch);end $$;

comment on table public.conference_accommodation_pricing is 'Canonical Accommodation-owned pricing configuration; calculated totals remain derived and Air Conditioning is deliberately excluded.';
commit;
