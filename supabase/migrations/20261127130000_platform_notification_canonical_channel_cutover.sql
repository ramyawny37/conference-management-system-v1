begin;

create table platform.notification_destinations(
  id uuid primary key default extensions.gen_random_uuid(),
  notification_event_id uuid not null references platform.notification_events(id) on delete cascade,
  destination_kind text not null check(destination_kind in('push_subscription','phone','email')),
  user_id uuid references platform.profiles(user_id) on delete cascade,
  push_subscription_id uuid references platform.notification_push_subscriptions(id) on delete restrict,
  destination text,
  created_at timestamptz not null default statement_timestamp(),
  check(
    (destination_kind='push_subscription' and user_id is not null and push_subscription_id is not null and destination is null)
    or (destination_kind in('phone','email') and user_id is null and push_subscription_id is null and destination is not null and char_length(destination) between 3 and 320)
  )
);
create unique index notification_destinations_push_uidx on platform.notification_destinations(notification_event_id,push_subscription_id) where push_subscription_id is not null;
create unique index notification_destinations_external_uidx on platform.notification_destinations(notification_event_id,destination_kind,destination) where destination is not null;
alter table platform.notification_destinations enable row level security;
alter table platform.notification_destinations force row level security;
revoke all on platform.notification_destinations from public,anon,authenticated,service_role;

create table platform.notification_channel_deliveries(
  id uuid primary key default extensions.gen_random_uuid(),
  notification_event_id uuid not null references platform.notification_events(id) on delete cascade,
  destination_id uuid not null references platform.notification_destinations(id) on delete cascade,
  channel text not null check(channel in('web_push','whatsapp','sms','email')),
  status text not null default 'pending' check(status in('pending','sent','failed','expired')),
  attempt_count integer not null default 0 check(attempt_count>=0),
  lease_token uuid,
  lease_expires_at timestamptz,
  next_attempt_at timestamptz,
  last_attempt_at timestamptz,
  delivered_at timestamptz,
  last_error_code text,
  provider_message_id text,
  created_at timestamptz not null default statement_timestamp(),
  unique(notification_event_id,destination_id,channel),
  check((lease_token is null)=(lease_expires_at is null))
);
create index notification_channel_deliveries_claim_idx on platform.notification_channel_deliveries(status,next_attempt_at,lease_expires_at,created_at) where status in('pending','failed');
alter table platform.notification_channel_deliveries enable row level security;
alter table platform.notification_channel_deliveries force row level security;
revoke all on platform.notification_channel_deliveries from public,anon,authenticated,service_role;

insert into platform.notification_destinations(notification_event_id,destination_kind,user_id,push_subscription_id)
select d.notification_event_id,'push_subscription',s.user_id,s.id
from platform.notification_deliveries d
join platform.notification_push_subscriptions s on s.id=d.subscription_id
on conflict do nothing;

insert into platform.notification_channel_deliveries(notification_event_id,destination_id,channel,status,attempt_count,lease_token,lease_expires_at,next_attempt_at,last_attempt_at,delivered_at,last_error_code,created_at)
select d.notification_event_id,nd.id,'web_push',d.status,d.attempt_count,d.lease_token,d.lease_expires_at,d.next_attempt_at,d.last_attempt_at,d.delivered_at,d.last_error_code,d.created_at
from platform.notification_deliveries d
join platform.notification_destinations nd on nd.notification_event_id=d.notification_event_id and nd.destination_kind='push_subscription' and nd.push_subscription_id=d.subscription_id
on conflict do nothing;

create or replace function platform_private.enqueue_notification_core(
  p_event_type text,p_module_key text,p_resource_type text,p_resource_id text,p_scope_type text,p_scope_id text,
  p_title text,p_body text,p_target_url text,p_dedupe_key text
) returns jsonb language plpgsql security definer set search_path='' as $function$
declare
  event_id uuid;
  inserted boolean:=false;
  delivery_count integer;
  recipient_count integer;
begin
  if p_module_key not in('conference','reservations','warehouse','platform')
    or p_event_type !~ '^[a-z0-9_.-]{3,120}$'
    or p_resource_type !~ '^[a-z0-9_.-]{1,80}$'
    or ((p_scope_type is null)<>(p_scope_id is null))
    or (p_scope_type is not null and p_scope_type !~ '^[a-z0-9_.-]{1,80}$')
    or (p_module_key='reservations' and (p_scope_type is distinct from 'event' or p_scope_id is null))
    or char_length(coalesce(p_title,'')) not between 1 and 160
    or char_length(coalesce(p_body,'')) not between 1 and 500
    or char_length(coalesce(p_target_url,'')) not between 1 and 1000
    or char_length(coalesce(p_dedupe_key,'')) not between 1 and 240
  then raise exception 'PLATFORM_NOTIFICATION_EVENT_INVALID' using errcode='22023'; end if;

  insert into platform.notification_events(event_type,module_key,resource_type,resource_id,scope_type,scope_id,title,body,target_url,dedupe_key)
  values(p_event_type,p_module_key,p_resource_type,p_resource_id,p_scope_type,p_scope_id,p_title,p_body,p_target_url,p_dedupe_key)
  on conflict(dedupe_key) do nothing returning id into event_id;
  if event_id is null then select id into event_id from platform.notification_events where dedupe_key=p_dedupe_key; else inserted:=true; end if;

  insert into platform.notification_recipients(notification_event_id,user_id)
  select event_id,pr.user_id from platform.profiles pr
  where platform_private.notification_user_is_authorized(pr.user_id,p_module_key,p_scope_type,p_scope_id)
  on conflict do nothing;
  get diagnostics recipient_count=row_count;

  insert into platform.notification_destinations(notification_event_id,destination_kind,user_id,push_subscription_id)
  select event_id,'push_subscription',s.user_id,s.id
  from platform.notification_push_subscriptions s
  join platform.notification_recipients r on r.notification_event_id=event_id and r.user_id=s.user_id
  where platform_private.notification_subscription_is_authorized(s.id,p_module_key,p_scope_type,p_scope_id)
  on conflict do nothing;

  insert into platform.notification_channel_deliveries(notification_event_id,destination_id,channel)
  select event_id,d.id,'web_push'
  from platform.notification_destinations d
  join platform.notification_push_subscriptions s on s.id=d.push_subscription_id
  where d.notification_event_id=event_id and d.destination_kind='push_subscription'
    and platform_private.notification_subscription_is_authorized(s.id,p_module_key,p_scope_type,p_scope_id)
  on conflict do nothing;
  get diagnostics delivery_count=row_count;

  return jsonb_build_object('notificationEventId',event_id,'created',inserted,'recipients',recipient_count,'queuedDeliveries',delivery_count);
end
$function$;
revoke all on function platform_private.enqueue_notification_core(text,text,text,text,text,text,text,text,text,text) from public,anon,authenticated,service_role;

create or replace function platform.notification_gateway(p_operation text,p_args jsonb)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare result jsonb; delivery_id uuid; status_value text; lease uuid;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'PLATFORM_NOTIFICATION_BACKEND_REQUIRED' using errcode='42501'; end if;
  if p_operation='enqueue' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['eventType','moduleKey','resourceType','resourceId','scopeType','scopeId','title','body','targetUrl','dedupeKey']);
    return platform_private.enqueue_notification(p_args->>'eventType',p_args->>'moduleKey',p_args->>'resourceType',p_args->>'resourceId',p_args->>'scopeType',p_args->>'scopeId',p_args->>'title',p_args->>'body',p_args->>'targetUrl',p_args->>'dedupeKey');
  elsif p_operation='claim' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['limit']);
    lease:=extensions.gen_random_uuid();
    with candidates as(
      select d.id
      from platform.notification_channel_deliveries d
      join platform.notification_destinations nd on nd.id=d.destination_id
      join platform.notification_push_subscriptions s on s.id=nd.push_subscription_id
      join platform.notification_events e on e.id=d.notification_event_id
      where d.channel='web_push' and nd.destination_kind='push_subscription'
        and d.status in('pending','failed') and d.attempt_count<5
        and(d.next_attempt_at is null or d.next_attempt_at<=statement_timestamp())
        and(d.lease_expires_at is null or d.lease_expires_at<=statement_timestamp())
        and platform_private.notification_subscription_is_authorized(s.id,e.module_key,e.scope_type,e.scope_id)
      order by d.notification_event_id,d.id
      for update of d skip locked
      limit least(greatest((p_args->>'limit')::int,1),100)
    ), claimed as(
      update platform.notification_channel_deliveries d
      set lease_token=lease,lease_expires_at=statement_timestamp()+interval '2 minutes'
      from candidates c where d.id=c.id returning d.*
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'deliveryId',d.id,'leaseToken',d.lease_token,'endpoint',s.endpoint,'p256dh',s.p256dh,'auth',s.auth_secret,
      'title',e.title,'body',e.body,'targetUrl',e.target_url,'eventType',e.event_type
    ) order by e.created_at,d.id),'[]'::jsonb) into result
    from claimed d
    join platform.notification_destinations nd on nd.id=d.destination_id
    join platform.notification_push_subscriptions s on s.id=nd.push_subscription_id
    join platform.notification_events e on e.id=d.notification_event_id;
    return result;
  elsif p_operation='mark' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['deliveryId','leaseToken','status','errorCode']);
    delivery_id:=(p_args->>'deliveryId')::uuid; lease:=(p_args->>'leaseToken')::uuid; status_value:=p_args->>'status';
    if status_value not in('sent','failed','expired') then raise exception 'PLATFORM_NOTIFICATION_DELIVERY_STATUS_INVALID' using errcode='22023'; end if;
    update platform.notification_channel_deliveries
    set status=status_value,attempt_count=attempt_count+1,last_attempt_at=statement_timestamp(),
      last_error_code=nullif(p_args->>'errorCode',''),
      delivered_at=case when status_value='sent' then statement_timestamp() else delivered_at end,
      next_attempt_at=case when status_value='failed' then statement_timestamp()+make_interval(secs=>least(1800,30*(2^least(attempt_count,6)))) else null end,
      lease_token=null,lease_expires_at=null
    where id=delivery_id and channel='web_push' and lease_token=lease and lease_expires_at>statement_timestamp();
    if not found then raise exception 'PLATFORM_NOTIFICATION_DELIVERY_LEASE_INVALID' using errcode='42501'; end if;
    if status_value='expired' then
      update platform.notification_push_subscriptions s set active=false,updated_at=statement_timestamp()
      from platform.notification_channel_deliveries d
      join platform.notification_destinations nd on nd.id=d.destination_id
      where d.id=delivery_id and d.channel='web_push' and nd.destination_kind='push_subscription' and s.id=nd.push_subscription_id and s.active;
    end if;
    return jsonb_build_object('deliveryId',delivery_id,'status',status_value);
  else
    raise exception 'PLATFORM_NOTIFICATION_OPERATION_NOT_ALLOWED' using errcode='42501';
  end if;
end
$function$;

create or replace function platform_private.stage_public_registration_decision_notification()
returns trigger language plpgsql security definer set search_path='' as $function$
declare v_event_id uuid; v_title text; v_body text; v_target text; v_dedupe text; v_destination_id uuid;
begin
  if new.state not in('approved','rejected','waitlisted') or new.state is not distinct from old.state then return new; end if;
  v_title:=case new.state when 'approved' then 'تم اعتماد طلب التسجيل' when 'rejected' then 'تم رفض طلب التسجيل' else 'تم وضع طلب التسجيل في قائمة الانتظار' end;
  v_body:=case new.state when 'approved' then 'تم اعتماد طلب التسجيل الخاص بك.' when 'rejected' then 'تم رفض طلب التسجيل الخاص بك.' else 'تم وضع طلب التسجيل الخاص بك في قائمة الانتظار.' end;
  v_target:='./#/public-registration?requestReference='||new.request_reference;
  v_dedupe:='public-registration-decision:'||new.id::text||':'||new.revision::text;
  insert into platform.notification_events(event_type,module_key,resource_type,resource_id,scope_type,scope_id,title,body,target_url,dedupe_key)
  values('public_registration.decision','reservations','public_registration_request',new.id::text,'event',new.event_id::text,v_title,v_body,v_target,v_dedupe)
  on conflict(dedupe_key) do update set dedupe_key=excluded.dedupe_key returning id into v_event_id;
  insert into platform.notification_destinations(notification_event_id,destination_kind,destination)
  values(v_event_id,'phone',new.submitted_phone) on conflict do nothing;
  select id into v_destination_id from platform.notification_destinations
  where notification_event_id=v_event_id and destination_kind='phone' and destination=new.submitted_phone;
  insert into platform.notification_channel_deliveries(notification_event_id,destination_id,channel)
  values(v_event_id,v_destination_id,'whatsapp'),(v_event_id,v_destination_id,'sms') on conflict do nothing;
  return new;
end
$function$;
revoke all on function platform_private.stage_public_registration_decision_notification() from public,anon,authenticated,service_role;

with inserted_events as (
  insert into platform.notification_events(event_type,module_key,resource_type,resource_id,scope_type,scope_id,title,body,target_url,dedupe_key)
  select o.event_type,o.module_key,o.resource_type,r.id::text,o.scope_type,o.scope_id,
    case r.state when 'approved' then 'تم اعتماد طلب التسجيل' when 'rejected' then 'تم رفض طلب التسجيل' else 'تم وضع طلب التسجيل في قائمة الانتظار' end,
    case r.state when 'approved' then 'تم اعتماد طلب التسجيل الخاص بك.' when 'rejected' then 'تم رفض طلب التسجيل الخاص بك.' else 'تم وضع طلب التسجيل الخاص بك في قائمة الانتظار.' end,
    './#/public-registration?requestReference='||r.request_reference,o.dedupe_key
  from platform.notification_external_outbox o
  join reservations.public_registration_requests r on r.request_reference=o.resource_id
  on conflict(dedupe_key) do nothing
  returning id,dedupe_key
)
select count(*) from inserted_events;

insert into platform.notification_destinations(notification_event_id,destination_kind,destination)
select e.id,o.destination_kind,o.destination
from platform.notification_external_outbox o join platform.notification_events e on e.dedupe_key=o.dedupe_key
on conflict do nothing;

insert into platform.notification_channel_deliveries(notification_event_id,destination_id,channel)
select e.id,d.id,c.channel
from platform.notification_external_outbox o
join platform.notification_events e on e.dedupe_key=o.dedupe_key
join platform.notification_destinations d on d.notification_event_id=e.id and d.destination_kind=o.destination_kind and d.destination=o.destination
cross join lateral unnest(o.channels)c(channel)
on conflict do nothing;

drop trigger public_registration_decision_external_notification on reservations.public_registration_requests;
drop function platform_private.stage_public_registration_decision_external_notification();
create trigger public_registration_decision_notification after update of state on reservations.public_registration_requests
for each row execute function platform_private.stage_public_registration_decision_notification();

drop table platform.notification_external_outbox;
drop table platform.notification_deliveries;

commit;
