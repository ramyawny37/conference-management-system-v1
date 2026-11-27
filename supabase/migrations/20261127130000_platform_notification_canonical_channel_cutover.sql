begin;

create table platform.notification_destinations(
  id uuid primary key default extensions.gen_random_uuid(),
  notification_event_id uuid not null references platform.notification_events(id) on delete cascade,
  destination_kind text not null check(destination_kind in('push_subscription','phone','email')),
  user_id uuid references platform.profiles(user_id) on delete cascade,
  push_subscription_id uuid references platform.notification_push_subscriptions(id) on delete cascade,
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
  status text not null default 'pending' check(status in('pending','sending','sent','failed','expired')),
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
  check((lease_token is null)=(lease_expires_at is null)),
  check(status='sending' or lease_token is null)
);
create index notification_channel_deliveries_claim_idx on platform.notification_channel_deliveries(status,next_attempt_at,lease_expires_at,created_at);
alter table platform.notification_channel_deliveries enable row level security;
alter table platform.notification_channel_deliveries force row level security;
revoke all on platform.notification_channel_deliveries from public,anon,authenticated,service_role;

insert into platform.notification_destinations(notification_event_id,destination_kind,user_id,push_subscription_id)
select d.notification_event_id,'push_subscription',s.user_id,s.id from platform.notification_deliveries d join platform.notification_push_subscriptions s on s.id=d.subscription_id on conflict do nothing;

insert into platform.notification_channel_deliveries(notification_event_id,destination_id,channel,status,attempt_count,last_attempt_at,delivered_at,last_error_code,next_attempt_at,created_at)
select d.notification_event_id,nd.id,'web_push',d.status,d.attempt_count,d.last_attempt_at,d.delivered_at,d.last_error_code,d.next_attempt_at,d.created_at
from platform.notification_deliveries d
join platform.notification_destinations nd on nd.notification_event_id=d.notification_event_id and nd.destination_kind='push_subscription' and nd.push_subscription_id=d.subscription_id
on conflict do nothing;

create or replace function platform_private.stage_public_registration_decision_notification()
returns trigger language plpgsql security definer set search_path='' as $$
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
 select id into v_destination_id from platform.notification_destinations where notification_event_id=v_event_id and destination_kind='phone' and destination=new.submitted_phone;
 insert into platform.notification_channel_deliveries(notification_event_id,destination_id,channel)
 values(v_event_id,v_destination_id,'whatsapp'),(v_event_id,v_destination_id,'sms') on conflict do nothing;
 return new;
end$$;
revoke all on function platform_private.stage_public_registration_decision_notification() from public,anon,authenticated,service_role;

-- Preserve already staged decisions by materializing them into the canonical event/destination/delivery graph.
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
create trigger public_registration_decision_notification after update of state on reservations.public_registration_requests for each row execute function platform_private.stage_public_registration_decision_notification();
drop table platform.notification_external_outbox;

commit;