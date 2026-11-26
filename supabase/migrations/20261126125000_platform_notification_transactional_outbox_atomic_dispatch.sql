begin;
create or replace function platform_private.dispatch_staged_notification() returns trigger language plpgsql security definer set search_path='' as $$begin perform platform_private.enqueue_notification_core(new.event_type,new.module_key,new.resource_type,new.resource_id,new.scope_type,new.scope_id,new.title,new.body,new.target_url,new.dedupe_key);update platform.notification_outbox set dispatched_at=statement_timestamp() where id=new.id;return new;end$$;
revoke all on function platform_private.dispatch_staged_notification() from public,anon,authenticated,service_role;
create trigger notification_outbox_dispatch after insert on platform.notification_outbox for each row execute function platform_private.dispatch_staged_notification();
commit;