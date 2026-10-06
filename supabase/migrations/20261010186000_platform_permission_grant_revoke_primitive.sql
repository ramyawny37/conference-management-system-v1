begin;
create or replace function platform_private.revoke_permission_grant(
 p_actor uuid,p_device uuid,p_grant uuid,p_reason text default null
) returns uuid language plpgsql security definer set search_path='' as $$
begin
 if p_actor is null or p_grant is null then raise exception 'INVALID_PERMISSION_REVOKE' using errcode='22023'; end if;
 if not exists(select 1 from platform.permission_grants where id=p_grant) then raise exception 'PERMISSION_GRANT_NOT_FOUND' using errcode='P0002'; end if;
 update platform.permission_grants
 set revoked_at=coalesce(revoked_at,now()),
     revoked_by=case when revoked_at is null then p_actor else revoked_by end,
     metadata=case when revoked_at is null then metadata||jsonb_build_object('revokedByDeviceId',p_device,'revocationReason',p_reason) else metadata end
 where id=p_grant;
 return p_grant;
end $$;
revoke all on function platform_private.revoke_permission_grant(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function platform_private.revoke_permission_grant(uuid,uuid,uuid,text) to service_role;
commit;