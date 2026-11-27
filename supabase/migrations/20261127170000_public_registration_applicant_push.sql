begin;
create table platform.notification_applicant_push_subscriptions(
 id uuid primary key default extensions.gen_random_uuid(),
 request_id uuid not null references reservations.public_registration_requests(id) on delete cascade,
 endpoint text not null,
 p256dh text not null,
 auth_secret text not null,
 user_agent text,
 active boolean not null default true,
 created_at timestamptz not null default statement_timestamp(),
 updated_at timestamptz not null default statement_timestamp(),
 unique(request_id,endpoint)
);
alter table platform.notification_applicant_push_subscriptions enable row level security;
alter table platform.notification_applicant_push_subscriptions force row level security;
revoke all on platform.notification_applicant_push_subscriptions from public,anon,authenticated,service_role;

alter table platform.notification_destinations add column applicant_push_subscription_id uuid references platform.notification_applicant_push_subscriptions(id) on delete restrict;
alter table platform.notification_destinations drop constraint notification_destinations_destination_kind_check;
alter table platform.notification_destinations drop constraint notification_destinations_check;
alter table platform.notification_destinations add constraint notification_destinations_destination_kind_check check(destination_kind in('push_subscription','applicant_push_subscription','phone','email'));
alter table platform.notification_destinations add constraint notification_destinations_check check(
 (destination_kind='push_subscription' and user_id is not null and push_subscription_id is not null and applicant_push_subscription_id is null and destination is null)
 or (destination_kind='applicant_push_subscription' and user_id is null and push_subscription_id is null and applicant_push_subscription_id is not null and destination is null)
 or (destination_kind in('phone','email') and user_id is null and push_subscription_id is null and applicant_push_subscription_id is null and destination is not null and char_length(destination) between 3 and 320)
);
create unique index notification_destinations_applicant_push_uidx on platform.notification_destinations(notification_event_id,applicant_push_subscription_id) where applicant_push_subscription_id is not null;

create or replace function reservations.public_registration_upsert_push_subscription(p_public_id uuid,p_tracking_secret_digest bytea,p_endpoint text,p_p256dh text,p_auth text,p_user_agent text)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_request_id uuid; v_id uuid;
begin
 if char_length(coalesce(p_endpoint,'')) not between 20 and 4096 or char_length(coalesce(p_p256dh,'')) not between 20 and 512 or char_length(coalesce(p_auth,'')) not between 8 and 256 or char_length(coalesce(p_user_agent,''))>512 then raise exception 'PUBLIC_REGISTRATION_PUSH_SUBSCRIPTION_INVALID' using errcode='22023'; end if;
 select r.id into v_request_id from reservations.public_registration_requests r join reservations.public_registration_channels c on c.id=r.channel_id where c.public_id=p_public_id and r.tracking_secret_digest=p_tracking_secret_digest;
 if v_request_id is null then raise exception 'PUBLIC_REGISTRATION_TRACKING_INVALID' using errcode='42501'; end if;
 insert into platform.notification_applicant_push_subscriptions(request_id,endpoint,p256dh,auth_secret,user_agent,active)
 values(v_request_id,p_endpoint,p_p256dh,p_auth,p_user_agent,true)
 on conflict(request_id,endpoint) do update set p256dh=excluded.p256dh,auth_secret=excluded.auth_secret,user_agent=excluded.user_agent,active=true,updated_at=statement_timestamp()
 returning id into v_id;
 return jsonb_build_object('subscriptionId',v_id,'active',true);
end $function$;
revoke all on function reservations.public_registration_upsert_push_subscription(uuid,bytea,text,text,text,text) from public,anon,authenticated,service_role;

create or replace function reservations.public_registration_disable_push_subscription(p_public_id uuid,p_tracking_secret_digest bytea,p_endpoint text)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_request_id uuid; v_changed int;
begin
 select r.id into v_request_id from reservations.public_registration_requests r join reservations.public_registration_channels c on c.id=r.channel_id where c.public_id=p_public_id and r.tracking_secret_digest=p_tracking_secret_digest;
 if v_request_id is null then raise exception 'PUBLIC_REGISTRATION_TRACKING_INVALID' using errcode='42501'; end if;
 update platform.notification_applicant_push_subscriptions set active=false,updated_at=statement_timestamp() where request_id=v_request_id and endpoint=p_endpoint and active;
 get diagnostics v_changed=row_count;
 return jsonb_build_object('active',false,'changed',v_changed>0);
end $function$;
revoke all on function reservations.public_registration_disable_push_subscription(uuid,bytea,text) from public,anon,authenticated,service_role;

create or replace function public.public_registration_gateway(p_operation text,p_args jsonb) returns jsonb language plpgsql security definer set search_path='' as $function$
begin
 if p_operation='event' then perform platform_private.require_exact_jsonb_keys(p_args,array['fingerprintDigest','publicId']);return reservations.public_registration_read((p_args->>'publicId')::uuid,decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'));
 elsif p_operation='status_family' then perform platform_private.require_exact_jsonb_keys(p_args,array['fingerprintDigest','publicId','trackingSecretDigest']);return reservations.public_registration_status_family((p_args->>'publicId')::uuid,decode(replace(p_args->>'trackingSecretDigest',chr(92)||'x',''),'hex'),decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'));
 elsif p_operation='recover_family' then perform platform_private.require_exact_jsonb_keys(p_args,array['dateOfBirth','fingerprintDigest','fullName','newTrackingSecretDigest','phone','publicId']);return reservations.public_registration_recover_family((p_args->>'publicId')::uuid,p_args->>'fullName',p_args->>'phone',(p_args->>'dateOfBirth')::date,decode(replace(p_args->>'newTrackingSecretDigest',chr(92)||'x',''),'hex'),decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'));
 elsif p_operation='submit_family' then perform platform_private.require_exact_jsonb_keys(p_args,array['fingerprintDigest','members','publicId','submitOperationId','trackingSecretDigest']);return reservations.public_registration_submit_family((p_args->>'publicId')::uuid,(p_args->>'submitOperationId')::uuid,decode(replace(p_args->>'trackingSecretDigest',chr(92)||'x',''),'hex'),decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'),p_args->'members');
 elsif p_operation='upsert_push_subscription' then perform platform_private.require_exact_jsonb_keys(p_args,array['auth','endpoint','p256dh','publicId','trackingSecretDigest','userAgent']);return reservations.public_registration_upsert_push_subscription((p_args->>'publicId')::uuid,decode(replace(p_args->>'trackingSecretDigest',chr(92)||'x',''),'hex'),p_args->>'endpoint',p_args->>'p256dh',p_args->>'auth',p_args->>'userAgent');
 elsif p_operation='disable_push_subscription' then perform platform_private.require_exact_jsonb_keys(p_args,array['endpoint','publicId','trackingSecretDigest']);return reservations.public_registration_disable_push_subscription((p_args->>'publicId')::uuid,decode(replace(p_args->>'trackingSecretDigest',chr(92)||'x',''),'hex'),p_args->>'endpoint');
 end if; raise exception 'PUBLIC_REGISTRATION_OPERATION_NOT_ALLOWED' using errcode='22023';
end $function$;
revoke all on function public.public_registration_gateway(text,jsonb) from public,anon,authenticated; grant execute on function public.public_registration_gateway(text,jsonb) to service_role;

create or replace function platform_private.stage_public_registration_decision_notification() returns trigger language plpgsql security definer set search_path='' as $function$
declare v_event_id uuid;v_title text;v_body text;v_target text;v_dedupe text;v_destination_id uuid;v_public_id uuid;
begin
 if new.state not in('approved','rejected','waitlisted') or new.state is not distinct from old.state then return new;end if;
 select c.public_id into v_public_id from reservations.public_registration_channels c where c.id=new.channel_id;
 v_title:=case new.state when 'approved' then 'تم اعتماد طلب التسجيل' when 'rejected' then 'تم رفض طلب التسجيل' else 'تم وضع طلب التسجيل في قائمة الانتظار' end;
 v_body:=case new.state when 'approved' then 'تم اعتماد طلب التسجيل الخاص بك.' when 'rejected' then 'تم رفض طلب التسجيل الخاص بك.' else 'تم وضع طلب التسجيل الخاص بك في قائمة الانتظار.' end;
 v_target:='./public-registration.html?event='||v_public_id::text;
 v_dedupe:='public-registration-decision:'||new.id::text||':'||new.revision::text;
 insert into platform.notification_events(event_type,module_key,resource_type,resource_id,scope_type,scope_id,title,body,target_url,dedupe_key) values('public_registration.decision','reservations','public_registration_request',new.id::text,'event',new.event_id::text,v_title,v_body,v_target,v_dedupe) on conflict(dedupe_key) do update set dedupe_key=excluded.dedupe_key returning id into v_event_id;
 insert into platform.notification_destinations(notification_event_id,destination_kind,destination) values(v_event_id,'phone',new.submitted_phone) on conflict do nothing;
 select id into v_destination_id from platform.notification_destinations where notification_event_id=v_event_id and destination_kind='phone' and destination=new.submitted_phone;
 insert into platform.notification_channel_deliveries(notification_event_id,destination_id,channel) values(v_event_id,v_destination_id,'whatsapp'),(v_event_id,v_destination_id,'sms') on conflict do nothing;
 insert into platform.notification_destinations(notification_event_id,destination_kind,applicant_push_subscription_id)
 select v_event_id,'applicant_push_subscription',s.id from platform.notification_applicant_push_subscriptions s where s.request_id=new.id and s.active on conflict do nothing;
 insert into platform.notification_channel_deliveries(notification_event_id,destination_id,channel)
 select v_event_id,d.id,'web_push' from platform.notification_destinations d where d.notification_event_id=v_event_id and d.destination_kind='applicant_push_subscription' on conflict do nothing;
 return new;
end $function$;
revoke all on function platform_private.stage_public_registration_decision_notification() from public,anon,authenticated,service_role;

create or replace function platform.notification_gateway(p_operation text,p_args jsonb) returns jsonb language plpgsql security definer set search_path='' as $function$
declare result jsonb;delivery_id uuid;status_value text;lease uuid;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'PLATFORM_NOTIFICATION_BACKEND_REQUIRED' using errcode='42501';end if;
 if p_operation='enqueue' then perform platform_private.require_exact_jsonb_keys(p_args,array['eventType','moduleKey','resourceType','resourceId','scopeType','scopeId','title','body','targetUrl','dedupeKey']);return platform_private.enqueue_notification(p_args->>'eventType',p_args->>'moduleKey',p_args->>'resourceType',p_args->>'resourceId',p_args->>'scopeType',p_args->>'scopeId',p_args->>'title',p_args->>'body',p_args->>'targetUrl',p_args->>'dedupeKey');
 elsif p_operation='claim' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['limit']);lease:=extensions.gen_random_uuid();
  with candidates as(select d.id from platform.notification_channel_deliveries d join platform.notification_destinations nd on nd.id=d.destination_id left join platform.notification_push_subscriptions ps on ps.id=nd.push_subscription_id left join platform.notification_applicant_push_subscriptions aps on aps.id=nd.applicant_push_subscription_id join platform.notification_events e on e.id=d.notification_event_id where d.channel='web_push' and d.status in('pending','failed') and d.attempt_count<5 and(d.next_attempt_at is null or d.next_attempt_at<=statement_timestamp()) and(d.lease_expires_at is null or d.lease_expires_at<=statement_timestamp()) and((nd.destination_kind='push_subscription' and ps.active and platform_private.notification_subscription_is_authorized(ps.id,e.module_key,e.scope_type,e.scope_id)) or(nd.destination_kind='applicant_push_subscription' and aps.active and aps.request_id::text=e.resource_id and e.event_type='public_registration.decision')) order by d.notification_event_id,d.id for update of d skip locked limit least(greatest((p_args->>'limit')::int,1),100)),claimed as(update platform.notification_channel_deliveries d set lease_token=lease,lease_expires_at=statement_timestamp()+interval '2 minutes' from candidates c where d.id=c.id returning d.*)
  select coalesce(jsonb_agg(jsonb_build_object('deliveryId',d.id,'leaseToken',d.lease_token,'notificationEventId',e.id,'audience',case when nd.destination_kind='applicant_push_subscription' then 'applicant' else 'platform' end,'endpoint',coalesce(ps.endpoint,aps.endpoint),'p256dh',coalesce(ps.p256dh,aps.p256dh),'auth',coalesce(ps.auth_secret,aps.auth_secret),'title',e.title,'body',e.body,'targetUrl',e.target_url,'eventType',e.event_type) order by e.created_at,d.id),'[]'::jsonb) into result from claimed d join platform.notification_destinations nd on nd.id=d.destination_id left join platform.notification_push_subscriptions ps on ps.id=nd.push_subscription_id left join platform.notification_applicant_push_subscriptions aps on aps.id=nd.applicant_push_subscription_id join platform.notification_events e on e.id=d.notification_event_id;return result;
 elsif p_operation='mark' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['deliveryId','leaseToken','status','errorCode']);delivery_id:=(p_args->>'deliveryId')::uuid;lease:=(p_args->>'leaseToken')::uuid;status_value:=p_args->>'status';if status_value not in('sent','failed','expired') then raise exception 'PLATFORM_NOTIFICATION_DELIVERY_STATUS_INVALID' using errcode='22023';end if;
  update platform.notification_channel_deliveries set status=status_value,attempt_count=attempt_count+1,last_attempt_at=statement_timestamp(),last_error_code=nullif(p_args->>'errorCode',''),delivered_at=case when status_value='sent' then statement_timestamp() else delivered_at end,next_attempt_at=case when status_value='failed' then statement_timestamp()+make_interval(secs=>least(1800,30*(2^least(attempt_count,6)))) else null end,lease_token=null,lease_expires_at=null where id=delivery_id and channel='web_push' and lease_token=lease and lease_expires_at>statement_timestamp();if not found then raise exception 'PLATFORM_NOTIFICATION_DELIVERY_LEASE_INVALID' using errcode='42501';end if;
  if status_value='expired' then update platform.notification_push_subscriptions s set active=false,updated_at=statement_timestamp() from platform.notification_channel_deliveries d join platform.notification_destinations nd on nd.id=d.destination_id where d.id=delivery_id and nd.push_subscription_id=s.id;update platform.notification_applicant_push_subscriptions s set active=false,updated_at=statement_timestamp() from platform.notification_channel_deliveries d join platform.notification_destinations nd on nd.id=d.destination_id where d.id=delivery_id and nd.applicant_push_subscription_id=s.id;end if;return jsonb_build_object('deliveryId',delivery_id,'status',status_value);
 else raise exception 'PLATFORM_NOTIFICATION_OPERATION_NOT_ALLOWED' using errcode='42501';end if;
end $function$;
revoke all on function platform.notification_gateway(text,jsonb) from public,anon,authenticated;grant execute on function platform.notification_gateway(text,jsonb) to service_role;
commit;
