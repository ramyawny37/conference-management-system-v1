begin;
create or replace function platform_private.resource_lease_session_owner(p_device uuid,p_session uuid) returns boolean language sql stable security definer set search_path='' as $$ select p_session=platform_private.require_resource_lease_session(p_device) $$;
revoke all on function platform_private.resource_lease_session_owner(uuid,uuid) from public,anon,authenticated;
commit;