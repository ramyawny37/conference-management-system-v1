begin;
alter table platform.notification_push_subscriptions add column app_base_path text;
alter table platform.notification_push_subscriptions add constraint notification_push_subscriptions_app_base_path_chk check(app_base_path is null or(char_length(app_base_path) between 2 and 240 and app_base_path like '/%/' and app_base_path !~ '[?#]' and app_base_path !~ '\\.\\.'));
update platform.notification_push_subscriptions set active=false,updated_at=statement_timestamp() where active and app_base_path is null;

create or replace function platform_private.upsert_notification_push_subscription(p_actor_device_id uuid,p_endpoint text,p_p256dh text,p_auth text,p_module_keys text[],p_user_agent text,p_app_base_path text) returns jsonb language plpgsql security definer set search_path='' as $function$
declare ctx jsonb;actor uuid;item text;row_id uuid;
begin
ctx:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;
if ctx is null or ctx->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or(ctx->>'device_id')::uuid is distinct from p_actor_device_id then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
actor:=(ctx->>'user_id')::uuid;
if p_endpoint is null or p_endpoint not like 'https://%' or char_length(p_endpoint)>2048 or char_length(coalesce(p_p256dh,'')) not between 40 and 256 or char_length(coalesce(p_auth,'')) not between 16 and 128 or cardinality(p_module_keys)=0 or p_module_keys is distinct from array(select distinct x from unnest(p_module_keys)x order by x) or p_app_base_path is null or char_length(p_app_base_path) not between 2 and 240 or p_app_base_path not like '/%/' or p_app_base_path ~ '[?#]' or p_app_base_path ~ '\\.\\.' then raise exception 'PLATFORM_NOTIFICATION_SUBSCRIPTION_INVALID' using errcode='22023';end if;
foreach item in array p_module_keys loop if item not in('conference','reservations','warehouse','platform') then raise exception 'PLATFORM_NOTIFICATION_MODULE_INVALID' using errcode='22023';end if;if item<>'platform' then perform public.require_effective_module_permission(p_actor_device_id,item,item||'.module.access',null,null);end if;end loop;
insert into platform.notification_push_subscriptions(user_id,device_id,endpoint,p256dh,auth_secret,module_keys,user_agent,app_base_path) values(actor,p_actor_device_id,p_endpoint,p_p256dh,p_auth,p_module_keys,left(coalesce(p_user_agent,''),512),p_app_base_path)
on conflict(endpoint) do update set user_id=excluded.user_id,device_id=excluded.device_id,p256dh=excluded.p256dh,auth_secret=excluded.auth_secret,module_keys=excluded.module_keys,user_agent=excluded.user_agent,app_base_path=excluded.app_base_path,active=true,updated_at=statement_timestamp() returning id into row_id;
return jsonb_build_object('subscriptionId',row_id,'active',true,'moduleKeys',p_module_keys,'appBasePath',p_app_base_path);
end$function$;
revoke all on function platform_private.upsert_notification_push_subscription(uuid,text,text,text,text[],text,text) from public,anon,authenticated,service_role;

create or replace function platform_private.get_notification_push_subscription_state(p_actor_device_id uuid,p_endpoint text,p_app_base_path text) returns jsonb language plpgsql security definer set search_path='' as $function$
declare ctx jsonb;actor uuid;s platform.notification_push_subscriptions%rowtype;
begin
ctx:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;
if ctx is null or ctx->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or(ctx->>'device_id')::uuid is distinct from p_actor_device_id then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
actor:=(ctx->>'user_id')::uuid;
if p_endpoint is null or p_endpoint not like 'https://%' or char_length(p_endpoint)>2048 or p_app_base_path is null or char_length(p_app_base_path) not between 2 and 240 or p_app_base_path not like '/%/' or p_app_base_path ~ '[?#]' or p_app_base_path ~ '\\.\\.' then raise exception 'PLATFORM_NOTIFICATION_SUBSCRIPTION_INVALID' using errcode='22023';end if;
select * into s from platform.notification_push_subscriptions where user_id=actor and device_id=p_actor_device_id and endpoint=p_endpoint and app_base_path=p_app_base_path limit 1;
return jsonb_build_object('registered',found,'active',coalesce(s.active,false),'moduleKeys',coalesce(to_jsonb(s.module_keys),'[]'::jsonb),'updatedAt',s.updated_at,'appBasePath',s.app_base_path);
end$function$;
revoke all on function platform_private.get_notification_push_subscription_state(uuid,text,text) from public,anon,authenticated,service_role;

do $patch$ declare source_sql text;updated_sql text;
begin
source_sql:=pg_get_functiondef('platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)'::regprocedure);
updated_sql:=replace(source_sql,'perform platform_private.require_exact_jsonb_keys(p_args,array[''p_endpoint'']);return platform_private.get_notification_push_subscription_state(v_session.device_id,p_args->>''p_endpoint'');','perform platform_private.require_exact_jsonb_keys(p_args,array[''p_endpoint'',''p_app_base_path'']);return platform_private.get_notification_push_subscription_state(v_session.device_id,p_args->>''p_endpoint'',p_args->>''p_app_base_path'');');
updated_sql:=replace(updated_sql,'perform platform_private.require_exact_jsonb_keys(p_args,array[''p_endpoint'',''p_p256dh'',''p_auth'',''p_module_keys'',''p_user_agent'']);','perform platform_private.require_exact_jsonb_keys(p_args,array[''p_endpoint'',''p_p256dh'',''p_auth'',''p_module_keys'',''p_user_agent'',''p_app_base_path'']);');
updated_sql:=replace(updated_sql,'return platform_private.upsert_notification_push_subscription(v_session.device_id,p_args->>''p_endpoint'',p_args->>''p_p256dh'',p_args->>''p_auth'',array(select jsonb_array_elements_text(p_args->''p_module_keys'')),p_args->>''p_user_agent'');','return platform_private.upsert_notification_push_subscription(v_session.device_id,p_args->>''p_endpoint'',p_args->>''p_p256dh'',p_args->>''p_auth'',array(select jsonb_array_elements_text(p_args->''p_module_keys'')),p_args->>''p_user_agent'',p_args->>''p_app_base_path'');');
if updated_sql=source_sql or position('p_app_base_path' in updated_sql)=0 then raise exception 'PLATFORM_NOTIFICATION_DEPLOYMENT_DISPATCHER_DRIFT';end if;execute updated_sql;
end$patch$;
drop function platform_private.upsert_notification_push_subscription(uuid,text,text,text,text[],text);
drop function platform_private.get_notification_push_subscription_state(uuid,text);

create or replace function platform.notification_gateway(p_operation text,p_args jsonb) returns jsonb language plpgsql security definer set search_path='' as $function$
declare result jsonb;delivery_id uuid;status_value text;lease uuid;
begin
if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'PLATFORM_NOTIFICATION_BACKEND_REQUIRED' using errcode='42501';end if;
if p_operation='enqueue' then perform platform_private.require_exact_jsonb_keys(p_args,array['eventType','moduleKey','resourceType','resourceId','scopeType','scopeId','title','body','targetUrl','dedupeKey']);return platform_private.enqueue_notification(p_args->>'eventType',p_args->>'moduleKey',p_args->>'resourceType',p_args->>'resourceId',p_args->>'scopeType',p_args->>'scopeId',p_args->>'title',p_args->>'body',p_args->>'targetUrl',p_args->>'dedupeKey');
elsif p_operation='claim' then
perform platform_private.require_exact_jsonb_keys(p_args,array['limit']);lease:=extensions.gen_random_uuid();
with candidates as(select d.id from platform.notification_channel_deliveries d join platform.notification_destinations nd on nd.id=d.destination_id join platform.notification_push_subscriptions s on s.id=nd.push_subscription_id join platform.notification_events e on e.id=d.notification_event_id where d.channel='web_push' and nd.destination_kind='push_subscription' and s.active and s.app_base_path is not null and d.status in('pending','failed') and d.attempt_count<5 and(d.next_attempt_at is null or d.next_attempt_at<=statement_timestamp()) and(d.lease_expires_at is null or d.lease_expires_at<=statement_timestamp()) and platform_private.notification_subscription_is_authorized(s.id,e.module_key,e.scope_type,e.scope_id) order by d.notification_event_id,d.id for update of d skip locked limit least(greatest((p_args->>'limit')::int,1),100)),
claimed as(update platform.notification_channel_deliveries d set lease_token=lease,lease_expires_at=statement_timestamp()+interval '2 minutes' from candidates c where d.id=c.id returning d.*)
select coalesce(jsonb_agg(jsonb_build_object('deliveryId',d.id,'leaseToken',d.lease_token,'endpoint',s.endpoint,'p256dh',s.p256dh,'auth',s.auth_secret,'title',e.title,'body',e.body,'targetUrl',e.target_url,'eventType',e.event_type,'notificationEventId',e.id,'appBasePath',s.app_base_path) order by e.created_at,d.id),'[]'::jsonb) into result from claimed d join platform.notification_destinations nd on nd.id=d.destination_id join platform.notification_push_subscriptions s on s.id=nd.push_subscription_id join platform.notification_events e on e.id=d.notification_event_id;return result;
elsif p_operation='mark' then
perform platform_private.require_exact_jsonb_keys(p_args,array['deliveryId','leaseToken','status','errorCode']);delivery_id:=(p_args->>'deliveryId')::uuid;lease:=(p_args->>'leaseToken')::uuid;status_value:=p_args->>'status';if status_value not in('sent','failed','expired') then raise exception 'PLATFORM_NOTIFICATION_DELIVERY_STATUS_INVALID' using errcode='22023';end if;
update platform.notification_channel_deliveries set status=status_value,attempt_count=attempt_count+1,last_attempt_at=statement_timestamp(),last_error_code=nullif(p_args->>'errorCode',''),delivered_at=case when status_value='sent' then statement_timestamp() else delivered_at end,next_attempt_at=case when status_value='failed' then statement_timestamp()+make_interval(secs=>least(1800,30*(2^least(attempt_count,6)))) else null end,lease_token=null,lease_expires_at=null where id=delivery_id and channel='web_push' and lease_token=lease and lease_expires_at>statement_timestamp();
if not found then raise exception 'PLATFORM_NOTIFICATION_DELIVERY_LEASE_INVALID' using errcode='42501';end if;
if status_value='expired' then update platform.notification_push_subscriptions s set active=false,updated_at=statement_timestamp() from platform.notification_channel_deliveries d join platform.notification_destinations nd on nd.id=d.destination_id where d.id=delivery_id and d.channel='web_push' and nd.destination_kind='push_subscription' and s.id=nd.push_subscription_id and s.active;end if;
return jsonb_build_object('deliveryId',delivery_id,'status',status_value);
else raise exception 'PLATFORM_NOTIFICATION_OPERATION_NOT_ALLOWED' using errcode='42501';end if;
end$function$;
commit;
