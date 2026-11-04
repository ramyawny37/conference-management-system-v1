begin;

do $$ begin
  if to_regclass('public.conference_accommodation_pricing') is null
     or to_regclass('public.conference_accommodation_rooms') is null
     or to_regprocedure('platform_private.conference_accommodation_pricing_projection(uuid)') is null
     or to_regprocedure('public.get_conference_accommodation(uuid,uuid)') is null
     or to_regprocedure('public.mutate_conference_accommodation_pricing(uuid,uuid,uuid,bigint,jsonb)') is null then
    raise exception 'C1A3_ACCOMMODATION_PRICING_FOUNDATION_REQUIRED' using errcode='55000';
  end if;
end $$;

create table public.conference_accommodation_pricing_room_exclusions(
  conference_id uuid not null,
  room_id uuid not null,
  created_at timestamptz not null default statement_timestamp(),
  created_by uuid not null references platform.profiles(user_id) on delete restrict,
  primary key(conference_id,room_id),
  constraint conference_accommodation_pricing_room_exclusions_room_fk
    foreign key(conference_id,room_id)
    references public.conference_accommodation_rooms(conference_id,id)
    on delete cascade
);
alter table public.conference_accommodation_pricing_room_exclusions enable row level security;
alter table public.conference_accommodation_pricing_room_exclusions force row level security;
revoke all on table public.conference_accommodation_pricing_room_exclusions from public,anon,authenticated,service_role;

do $$ declare sig regprocedure:='public.get_conference_accommodation(uuid,uuid)'::regprocedure;d text;
  marker text:='''revision'',r.revision,''occupancies'',';
  replacement text:='''revision'',r.revision,''includedInPricing'',not exists(select 1 from public.conference_accommodation_pricing_room_exclusions x where x.conference_id=r.conference_id and x.room_id=r.id),''occupancies'',';
begin
  d:=pg_get_functiondef(sig);
  if position(marker in d)=0 or position('''includedInPricing''' in d)<>0 then raise exception 'C1A3_ACCOMMODATION_READ_PRECONDITION_FAILED' using errcode='55000';end if;
  execute replace(d,marker,replacement);
end $$;

create or replace function public.mutate_conference_accommodation_pricing(p_actor_device_id uuid,p_operation_id uuid,p_conference_id uuid,p_expected_revision bigint,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare ctx jsonb;session_ctx jsonb;actor uuid;authz uuid;prior public.conference_participation_operations%rowtype;
  current_row public.conference_accommodation_pricing%rowtype;changed public.conference_accommodation_pricing%rowtype;
  req jsonb;result jsonb;mode text;vals numeric[];action text;v_room_id uuid;room public.conference_accommodation_rooms%rowtype;excluded boolean;was_excluded boolean;
begin
  if p_operation_id is null or p_conference_id is null or jsonb_typeof(p_payload)<>'object' then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ARGUMENT_INVALID' using errcode='22023';end if;
  if p_payload ? 'action' then
    perform platform_private.require_exact_jsonb_keys(p_payload,array['action','roomId']);
    action:=p_payload->>'action';
    if action not in('EXCLUDE_ROOM','REMOVE_ROOM_EXCLUSION') then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ARGUMENT_INVALID' using errcode='22023';end if;
    begin v_room_id:=(p_payload->>'roomId')::uuid;exception when others then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ARGUMENT_INVALID' using errcode='22023';end;
  else
    perform platform_private.require_exact_jsonb_keys(p_payload,array['enabled','pricingMode','prices','roomTypePrices']);
    perform platform_private.require_exact_jsonb_keys(p_payload->'prices',array['personNight','roomNight','personDay','roomDay','packagePrice','packageDayPrice']);
    perform platform_private.require_exact_jsonb_keys(p_payload->'roomTypePrices',array['single','double','triple','quadruple','quintuple','sextuple','sevenPlus']);
    mode:=p_payload->>'pricingMode';if mode not in('per_person_night','per_room_night','per_person_day','per_room_day','fixed_package','per_day_package','room_type') then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ARGUMENT_INVALID' using errcode='22023';end if;
    begin vals:=array[(p_payload->'prices'->>'personNight')::numeric,(p_payload->'prices'->>'roomNight')::numeric,(p_payload->'prices'->>'personDay')::numeric,(p_payload->'prices'->>'roomDay')::numeric,(p_payload->'prices'->>'packagePrice')::numeric,(p_payload->'prices'->>'packageDayPrice')::numeric,(p_payload->'roomTypePrices'->>'single')::numeric,(p_payload->'roomTypePrices'->>'double')::numeric,(p_payload->'roomTypePrices'->>'triple')::numeric,(p_payload->'roomTypePrices'->>'quadruple')::numeric,(p_payload->'roomTypePrices'->>'quintuple')::numeric,(p_payload->'roomTypePrices'->>'sextuple')::numeric,(p_payload->'roomTypePrices'->>'sevenPlus')::numeric];exception when others then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ARGUMENT_INVALID' using errcode='22023';end;
    if exists(select 1 from unnest(vals) v where v<0) then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ARGUMENT_INVALID' using errcode='22023';end if;
  end if;
  session_ctx:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;actor:=(session_ctx->>'user_id')::uuid;
  if session_ctx->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or (session_ctx->>'device_id')::uuid is distinct from p_actor_device_id then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
  authz:=platform_private.validated_phase1c_device_authorization(actor,p_actor_device_id);if authz is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
  ctx:=platform_private.require_conference_accommodation_context(p_actor_device_id,p_conference_id,'conference.accommodation.manage',true);
  if (ctx->>'actorUserId')::uuid is distinct from actor then raise exception 'ACTOR_DEVICE_OVERRIDE_DENIED' using errcode='42501';end if;
  req:=jsonb_build_object('conferenceId',p_conference_id,'expectedRevision',p_expected_revision,'payload',p_payload);
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into prior from public.conference_participation_operations where actor_user_id=actor and operation_id=p_operation_id;
  if found then if prior.operation<>'accommodation_pricing_mutation' or prior.request<>req then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';end if;return prior.result;end if;
  perform pg_advisory_xact_lock(hashtextextended('conference-accommodation-pricing:'||p_conference_id::text,0));
  select * into current_row from public.conference_accommodation_pricing where conference_id=p_conference_id for update;
  if found and (p_expected_revision is null or current_row.revision<>p_expected_revision) then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_REVISION_CONFLICT' using errcode='40001';end if;
  if not found and p_expected_revision is not null and p_expected_revision<>0 then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_REVISION_CONFLICT' using errcode='40001';end if;
  if action is not null then
    select * into room from public.conference_accommodation_rooms where id=v_room_id and conference_id=p_conference_id for update;
    if not found then raise exception 'ACCOMMODATION_ROOM_NOT_FOUND' using errcode='P0002';end if;
    excluded:=exists(select 1 from public.conference_accommodation_pricing_room_exclusions where conference_id=p_conference_id and room_id=v_room_id);
    was_excluded:=excluded;
    if (action='EXCLUDE_ROOM' and excluded) or (action='REMOVE_ROOM_EXCLUSION' and not excluded) then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ROOM_INCLUSION_UNCHANGED' using errcode='55000';end if;
    if current_row.conference_id is null then
      insert into public.conference_accommodation_pricing(conference_id,created_by,updated_by) values(p_conference_id,actor,actor) returning * into changed;
    else
      update public.conference_accommodation_pricing set revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where conference_id=p_conference_id returning * into changed;
    end if;
    if action='EXCLUDE_ROOM' then
      insert into public.conference_accommodation_pricing_room_exclusions(conference_id,room_id,created_by) values(p_conference_id,v_room_id,actor);excluded:=true;
    else
      delete from public.conference_accommodation_pricing_room_exclusions where conference_id=p_conference_id and room_id=v_room_id;excluded:=false;
    end if;
    result:=jsonb_build_object('conferenceId',p_conference_id,'roomId',v_room_id,'includedInPricing',not excluded,'pricing',platform_private.conference_accommodation_pricing_projection(p_conference_id));
    insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at) values(actor,p_operation_id,'accommodation_pricing_mutation',req,result,statement_timestamp());
    insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source)
    values(actor,authz,'platform','conference',case when excluded then 'conference.accommodation.pricing_room_excluded' else 'conference.accommodation.pricing_room_included' end,'conference_accommodation_pricing_room',v_room_id,'platform',jsonb_build_object('includedInPricing',not was_excluded),jsonb_build_object('includedInPricing',not excluded),jsonb_build_object('conferenceId',p_conference_id,'permissionKey','conference.accommodation.manage','authoritySource',ctx->>'authoritySource','grantId',ctx->'grantId'),p_operation_id,'rpc');
    return result;
  end if;
  insert into public.conference_accommodation_pricing(conference_id,enabled,pricing_mode,person_night,room_night,person_day,room_day,package_price,package_day_price,single_price,double_price,triple_price,quadruple_price,quintuple_price,sextuple_price,seven_plus_price,revision,created_by,updated_by)
  values(p_conference_id,(p_payload->>'enabled')::boolean,mode,vals[1],vals[2],vals[3],vals[4],vals[5],vals[6],vals[7],vals[8],vals[9],vals[10],vals[11],vals[12],vals[13],1,actor,actor)
  on conflict(conference_id) do update set enabled=excluded.enabled,pricing_mode=excluded.pricing_mode,person_night=excluded.person_night,room_night=excluded.room_night,person_day=excluded.person_day,room_day=excluded.room_day,package_price=excluded.package_price,package_day_price=excluded.package_day_price,single_price=excluded.single_price,double_price=excluded.double_price,triple_price=excluded.triple_price,quadruple_price=excluded.quadruple_price,quintuple_price=excluded.quintuple_price,sextuple_price=excluded.sextuple_price,seven_plus_price=excluded.seven_plus_price,revision=public.conference_accommodation_pricing.revision+1,updated_at=statement_timestamp(),updated_by=actor returning * into changed;
  result:=jsonb_build_object('conferenceId',p_conference_id,'pricing',platform_private.conference_accommodation_pricing_projection(p_conference_id));
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at) values(actor,p_operation_id,'accommodation_pricing_mutation',req,result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source) values(actor,authz,'platform','conference','conference.accommodation.pricing_updated','conference_accommodation_pricing',p_conference_id,'platform',case when current_row.conference_id is null then null else to_jsonb(current_row) end,to_jsonb(changed),jsonb_build_object('conferenceId',p_conference_id,'permissionKey','conference.accommodation.manage','authoritySource',ctx->>'authoritySource','grantId',ctx->'grantId'),p_operation_id,'rpc');
  return result;
exception when invalid_text_representation or null_value_not_allowed then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ARGUMENT_INVALID' using errcode='22023';
end $$;

revoke all on table public.conference_accommodation_pricing_room_exclusions from public,anon,authenticated,service_role;
revoke all on function public.mutate_conference_accommodation_pricing(uuid,uuid,uuid,bigint,jsonb),public.get_conference_accommodation(uuid,uuid) from public,anon,authenticated,service_role;
comment on table public.conference_accommodation_pricing_room_exclusions is 'Accommodation Pricing-owned exceptions only. Absence means the canonical room is included by default; no legacy room-selection initialization.';
commit;
