begin;
create or replace function platform_private.require_owned_accommodation_room_lease(
 p_actor_device_id uuid,p_room_id uuid,p_lease_token uuid
) returns void language plpgsql security definer set search_path='' as $$
declare v_session uuid;
begin
 if p_room_id is null or p_lease_token is null then
  raise exception 'RESOURCE_LEASE_REQUIRED' using errcode='42501';
 end if;
 v_session:=platform_private.require_resource_lease_session(p_actor_device_id);
 perform 1 from platform.resource_leases l
 where l.module_id='conference' and l.resource_type='accommodation_room'
  and l.resource_id=p_room_id::text and l.scope='edit'
  and l.holder_device_id=p_actor_device_id
  and l.holder_session_id=v_session
  and l.lease_token=p_lease_token
  and l.expires_at>pg_catalog.clock_timestamp()
 for update;
 if not found then
  raise exception 'RESOURCE_LEASE_NOT_OWNED' using errcode='42501';
 end if;
end $$;
revoke all on function platform_private.require_owned_accommodation_room_lease(uuid,uuid,uuid) from public,anon,authenticated;
commit;