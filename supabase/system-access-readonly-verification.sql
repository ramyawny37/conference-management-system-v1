-- Read-only verification for canonical Platform account authority.
-- Legacy public.system_user_access/public.system_user_roles are intentionally retired.

select 'platform_owners' as check_name, count(*)::bigint as result
from platform.user_roles as user_roles
join platform.roles as roles on roles.id = user_roles.role_id
where roles.code = 'platform_owner'
union all
select 'platform_admins', count(*)::bigint
from platform.user_roles as user_roles
join platform.roles as roles on roles.id = user_roles.role_id
where roles.code = 'platform_admin'
union all
select 'approved_accounts', count(*)::bigint
from platform.profiles
where account_status = 'approved'
union all
select 'pending_accounts', count(*)::bigint
from platform.profiles
where account_status = 'pending'
union all
select 'blocked_accounts', count(*)::bigint
from platform.profiles
where account_status = 'blocked'
union all
select 'users_missing_platform_profile', count(*)::bigint
from auth.users as users
where not exists (
  select 1
  from platform.profiles as profiles
  where profiles.user_id = users.id
)
union all
select 'conference_owners_not_approved', count(*)::bigint
from (
  select distinct conferences.owner_id
  from public.conferences as conferences
  left join platform.profiles as profiles
    on profiles.user_id = conferences.owner_id
  where profiles.user_id is null
     or profiles.account_status <> 'approved'
) as invalid_owners;
