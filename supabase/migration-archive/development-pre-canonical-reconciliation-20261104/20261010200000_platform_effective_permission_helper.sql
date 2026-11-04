begin;

create or replace function platform_private.has_effective_platform_permission(
  p_user_id uuid,
  p_permission_code text
) returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select
    p_user_id is not null
    and p_permission_code like 'platform.%'
    and exists (
      select 1
      from platform.profiles profile
      where profile.user_id=p_user_id
        and profile.account_status='approved'
    )
    and (
      platform_private.is_canonical_platform_owner(p_user_id)
      or exists (
        select 1
        from platform.permission_grants grant_row
        join platform.permissions permission
          on permission.id=grant_row.permission_id
        where grant_row.user_id=p_user_id
          and grant_row.revoked_at is null
          and grant_row.scope_type='platform'
          and grant_row.resource_type is null
          and grant_row.resource_id is null
          and permission.domain='platform'
          and permission.code=p_permission_code
      )
    );
$$;

revoke all on function platform_private.has_effective_platform_permission(uuid,text)
from public,anon,authenticated,service_role;

commit;
