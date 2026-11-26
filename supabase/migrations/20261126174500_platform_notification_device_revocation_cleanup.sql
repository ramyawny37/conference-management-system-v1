begin;
create or replace function platform_private.retire_notification_push_subscriptions_for_device(p_user_id uuid,p_device_id uuid) returns integer language plpgsql security definer set search_path='' as $$declare changed integer;begin
update platform.notification_push_subscriptions
set active=false,updated_at=statement_timestamp()
where user_id=p_user_id and device_id=p_device_id and active;
get diagnostics changed=row_count;
return changed;
end$$;
revoke all on function platform_private.retire_notification_push_subscriptions_for_device(uuid,uuid) from public,anon,authenticated,service_role;

do $patch$
declare source_sql text;updated_sql text;needle text;
begin
source_sql:=pg_get_functiondef('public.complete_system_owner_pending_device_operation(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,uuid,text,bigint,text,text,jsonb)'::regprocedure);
if position('retire_notification_push_subscriptions_for_device' in source_sql)>0 then return;end if;
needle:='update platform_private.device_sessions set revoked_at=operation_at
    where user_id=p_target_user_id and device_id=p_target_device_id and revoked_at is null;';
if position(needle in source_sql)=0 then raise exception 'PLATFORM_NOTIFICATION_DEVICE_REVOCATION_DRIFT';end if;
updated_sql:=replace(source_sql,needle,needle||'
    perform platform_private.retire_notification_push_subscriptions_for_device(p_target_user_id,p_target_device_id);');
execute updated_sql;
end$patch$;
commit;
