begin;

do $$ begin
  if to_regclass('public.conferences') is null
     or to_regclass('public.conference_participation_operations') is null
     or to_regprocedure('platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)') is null
     or not exists(select 1 from public.module_permission_catalog where permission_key='conference.cards.view' and status='active')
     or not exists(select 1 from public.module_permission_catalog where permission_key='conference.lifecycle.manage' and status='active') then
    raise exception 'C1A2_CANONICAL_CONFERENCE_FOUNDATION_REQUIRED' using errcode='55000';
  end if;
end $$;

create function platform_private.is_prepared_jpeg_data_url(p_value text)
returns boolean language plpgsql immutable security definer set search_path='' as $$
declare payload text; decoded bytea;
begin
  if p_value is null or p_value !~ '^data:image/jpeg;base64,[A-Za-z0-9+/]+={0,2}$' then return false; end if;
  payload:=substr(p_value,length('data:image/jpeg;base64,')+1);
  if length(payload)%4<>0 then return false; end if;
  begin decoded:=decode(payload,'base64'); exception when others then return false; end;
  return length(decoded)>=3 and get_byte(decoded,0)=255 and get_byte(decoded,1)=216 and get_byte(decoded,2)=255;
end $$;

create table public.conference_branding(
  conference_id uuid primary key references public.conferences(id) on delete cascade,
  banner text not null default '',
  service_logo text not null default '',
  auto_colors boolean not null default false,
  banner_position text not null default 'center' check(banner_position in('top','center','bottom')),
  card_theme text not null default 'classic' check(card_theme in('classic','modern-banner')),
  primary_color text not null default '#6C3483' check(primary_color~'^#[0-9A-Fa-f]{6}$'),
  secondary_color text not null default '#8E44AD' check(secondary_color~'^#[0-9A-Fa-f]{6}$'),
  text_color text not null default '#1A2A3A' check(text_color~'^#[0-9A-Fa-f]{6}$'),
  revision bigint not null default 1 check(revision>=1),
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  updated_by uuid references platform.profiles(user_id),
  check(banner='' or platform_private.is_prepared_jpeg_data_url(banner)),
  check(service_logo='' or platform_private.is_prepared_jpeg_data_url(service_logo))
);
alter table public.conference_branding enable row level security;
alter table public.conference_branding force row level security;
revoke all on table public.conference_branding from public,anon,authenticated,service_role;

insert into public.conference_branding(conference_id) select id from public.conferences on conflict do nothing;

create function platform_private.create_conference_branding_default()
returns trigger language plpgsql security definer set search_path='' as $$
begin insert into public.conference_branding(conference_id) values(new.id);return new;end $$;
create trigger conferences_create_branding_default after insert on public.conferences
for each row execute function platform_private.create_conference_branding_default();

alter table public.conference_participation_operations drop constraint conference_participation_operations_operation_check;
alter table public.conference_participation_operations add constraint conference_participation_operations_operation_check check(operation in(
  'create','create_with_person','set_status','set_guardian','delete',
  'transport_vehicle_create','transport_vehicle_update','transport_vehicle_delete',
  'transport_assignment_set','transport_assignment_remove','restaurant_mutation',
  'accommodation_pricing_mutation','air_conditioning_mutation','finance_mutation',
  'conference_core_mutation','conference_branding_mutation'
));

create function platform_private.require_conference_branding_context(p_device uuid,p_conference uuid,p_permission text,p_mutation boolean)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare session_ctx jsonb;ctx jsonb;actor uuid;conf public.conferences%rowtype;
begin
  if p_permission not in('conference.cards.view','conference.lifecycle.manage') then raise exception 'CONFERENCE_BRANDING_ARGUMENT_INVALID' using errcode='22023';end if;
  session_ctx:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;actor:=(session_ctx->>'user_id')::uuid;
  if session_ctx->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or (session_ctx->>'device_id')::uuid is distinct from p_device
     or platform_private.validated_phase1c_device_authorization(actor,p_device) is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
  ctx:=public.require_effective_module_permission(p_device,'conference',p_permission,'conference',p_conference::text);
  if (ctx->>'actorUserId')::uuid is distinct from actor then raise exception 'ACTOR_DEVICE_OVERRIDE_DENIED' using errcode='42501';end if;
  select * into conf from public.conferences where id=p_conference and deleted_at is null;
  if not found then raise exception 'CONFERENCE_NOT_FOUND' using errcode='P0002';end if;
  if p_mutation and conf.status<>'active' then raise exception 'COMPLETED_CONFERENCE_IMMUTABLE' using errcode='55000';end if;
  return ctx;
end $$;

create function platform_private.conference_branding_projection(p_conference uuid)
returns jsonb language sql stable security definer set search_path='' as $$
select jsonb_build_object('conferenceId',b.conference_id,'banner',b.banner,'serviceLogo',b.service_logo,
  'autoColors',b.auto_colors,'bannerPosition',b.banner_position,'cardTheme',b.card_theme,
  'primaryColor',b.primary_color,'secondaryColor',b.secondary_color,'textColor',b.text_color,
  'revision',b.revision,'updatedAt',b.updated_at,'updatedBy',b.updated_by)
from public.conference_branding b where b.conference_id=p_conference
$$;

create function public.get_conference_branding(p_device uuid,p_conference uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin perform platform_private.require_conference_branding_context(p_device,p_conference,'conference.cards.view',false);return platform_private.conference_branding_projection(p_conference);end $$;

create function public.mutate_conference_branding(p_device uuid,p_operation_id uuid,p_conference uuid,p_action text,p_expected_revision bigint,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare ctx jsonb;session_ctx jsonb;actor uuid;authz uuid;prior public.conference_participation_operations%rowtype;
  req jsonb;result jsonb;before_row public.conference_branding%rowtype;after_row public.conference_branding%rowtype;image_value text;
begin
  if p_operation_id is null or p_conference is null or p_expected_revision is null or p_expected_revision<1
     or p_action not in('SETTINGS_UPDATE','BANNER_SET','BANNER_REMOVE','SERVICE_LOGO_SET','SERVICE_LOGO_REMOVE')
     or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'CONFERENCE_BRANDING_ARGUMENT_INVALID' using errcode='22023';end if;
  session_ctx:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;actor:=(session_ctx->>'user_id')::uuid;
  if session_ctx->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or (session_ctx->>'device_id')::uuid is distinct from p_device then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
  authz:=platform_private.validated_phase1c_device_authorization(actor,p_device);if authz is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
  ctx:=platform_private.require_conference_branding_context(p_device,p_conference,'conference.lifecycle.manage',true);
  req:=jsonb_build_object('conferenceId',p_conference,'action',p_action,'expectedRevision',p_expected_revision,'payload',p_payload);
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into prior from public.conference_participation_operations where actor_user_id=actor and operation_id=p_operation_id;
  if found then if prior.operation<>'conference_branding_mutation' or prior.request<>req then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';end if;return prior.result;end if;
  select * into before_row from public.conference_branding where conference_id=p_conference for update;
  if not found then raise exception 'CONFERENCE_BRANDING_NOT_FOUND' using errcode='P0002';end if;
  if before_row.revision<>p_expected_revision then raise exception 'CONFERENCE_BRANDING_REVISION_CONFLICT' using errcode='40001';end if;
  if p_action='SETTINGS_UPDATE' then
    perform platform_private.require_exact_jsonb_keys(p_payload,array['autoColors','bannerPosition','cardTheme','primaryColor','secondaryColor','textColor']);
    update public.conference_branding set auto_colors=(p_payload->>'autoColors')::boolean,banner_position=p_payload->>'bannerPosition',card_theme=p_payload->>'cardTheme',primary_color=p_payload->>'primaryColor',secondary_color=p_payload->>'secondaryColor',text_color=p_payload->>'textColor',revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where conference_id=p_conference returning * into after_row;
  elsif p_action in('BANNER_SET','SERVICE_LOGO_SET') then
    perform platform_private.require_exact_jsonb_keys(p_payload,array['image']);image_value:=p_payload->>'image';
    if not platform_private.is_prepared_jpeg_data_url(image_value) then raise exception 'CONFERENCE_BRANDING_JPEG_DATA_URL_INVALID' using errcode='22023';end if;
    if p_action='BANNER_SET' then update public.conference_branding set banner=image_value,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where conference_id=p_conference returning * into after_row;
    else update public.conference_branding set service_logo=image_value,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where conference_id=p_conference returning * into after_row;end if;
  else
    perform platform_private.require_exact_jsonb_keys(p_payload,array[]::text[]);
    if p_action='BANNER_REMOVE' then update public.conference_branding set banner='',revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where conference_id=p_conference returning * into after_row;
    else update public.conference_branding set service_logo='',revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where conference_id=p_conference returning * into after_row;end if;
  end if;
  result:=platform_private.conference_branding_projection(p_conference);
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at) values(actor,p_operation_id,'conference_branding_mutation',req,result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source)
  values(actor,authz,'platform','conference','conference.branding.changed','conference_branding',p_conference,'platform',
    jsonb_build_object('revision',before_row.revision,'action',p_action),jsonb_build_object('revision',after_row.revision,'action',p_action),
    jsonb_build_object('conferenceId',p_conference,'permissionKey','conference.lifecycle.manage','authoritySource',ctx->>'authoritySource','grantId',ctx->'grantId'),p_operation_id,'rpc');
  return result;
end $$;

revoke all on function platform_private.is_prepared_jpeg_data_url(text),platform_private.create_conference_branding_default(),platform_private.require_conference_branding_context(uuid,uuid,text,boolean),platform_private.conference_branding_projection(uuid),public.get_conference_branding(uuid,uuid),public.mutate_conference_branding(uuid,uuid,uuid,text,bigint,jsonb) from public,anon,authenticated,service_role;

do $$ declare sig regprocedure:='platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)'::regprocedure;d text;
  marker text:='if p_operation=''get_conference_finance'' then';
  branch text:='if p_operation=''get_conference_branding'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_conference_id'']);return public.get_conference_branding(p_actor_device_id,(p_args->>''p_conference_id'')::uuid);elsif p_operation=''mutate_conference_branding'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_conference_id'',''p_action'',''p_expected_revision'',''p_payload'']);return public.mutate_conference_branding(p_actor_device_id,(p_args->>''p_operation_id'')::uuid,(p_args->>''p_conference_id'')::uuid,p_args->>''p_action'',(p_args->>''p_expected_revision'')::bigint,p_args->''p_payload'');elsif p_operation=''get_conference_finance'' then';
begin d:=pg_get_functiondef(sig);if position(marker in d)=0 then raise exception 'C1A2_BRANDING_ROUTE_PRECONDITION_FAILED' using errcode='55000';end if;execute replace(d,marker,branch);end $$;

comment on table public.conference_branding is 'One explicit canonical Branding owner per Conference. No legacy Branding or snapshot initialization.';
commit;
