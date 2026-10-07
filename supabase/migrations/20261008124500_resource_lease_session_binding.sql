begin;

alter table platform.resource_leases
  add column holder_session_id uuid references platform_private.device_sessions(id) on delete cascade;

create or replace function platform_private.require_resource_lease_session(p_actor_device_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_context jsonb; v_session uuid; v_user uuid;
begin
  begin
    v_context:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;
    v_session:=(v_context->>'session_id')::uuid;
    v_user:=(v_context->>'user_id')::uuid;
  exception when others then
    raise exception 'RESOURCE_LEASE_SESSION_REQUIRED' using errcode='42501';
  end;
  if v_context->>'purpose' is distinct from 'PLATFORM_DEVICE_SESSION_DISPATCH'
     or v_session is null or v_user is null
     or (v_context->>'device_id')::uuid is distinct from p_actor_device_id
     or not exists (
       select 1 from platform_private.device_sessions s
       where s.id=v_session and s.user_id=v_user and s.device_id=p_actor_device_id
         and s.purpose='PLATFORM_DEVICE_SESSION'
         and s.revoked_at is null and s.expires_at>pg_catalog.statement_timestamp()
     ) then
    raise exception 'RESOURCE_LEASE_SESSION_REQUIRED' using errcode='42501';
  end if;
  return v_session;
end $$;

create or replace function platform_private.enforce_resource_lease_session()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_session uuid;
begin
  v_session:=platform_private.require_resource_lease_session(
    case when tg_op='DELETE' then old.holder_device_id else new.holder_device_id end
  );
  if tg_op='INSERT' then
    new.holder_session_id:=v_session;
    return new;
  end if;
  if old.holder_session_id is distinct from v_session then
    raise exception 'RESOURCE_LEASE_SESSION_NOT_OWNED' using errcode='42501';
  end if;
  if tg_op='DELETE' then return old; end if;
  new.holder_session_id:=v_session;
  return new;
end $$;

create trigger resource_lease_session_guard
before insert or update or delete on platform.resource_leases
for each row execute function platform_private.enforce_resource_lease_session();

revoke all on function platform_private.require_resource_lease_session(uuid) from public,anon,authenticated;
revoke all on function platform_private.enforce_resource_lease_session() from public,anon,authenticated;

commit;
