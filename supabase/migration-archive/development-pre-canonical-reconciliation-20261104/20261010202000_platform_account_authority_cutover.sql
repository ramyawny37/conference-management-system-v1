-- Make Platform the sole authority for account approval and platform owner/admin decisions.
-- Existing public helper names remain only as callers' stable boundary; they no longer
-- read legacy System Access storage.

create or replace function public.is_system_owner(user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=''
as $$
 select user_id is not null and exists(
  select 1 from platform.user_roles a
  join platform.roles r on r.id=a.role_id
  where a.user_id=is_system_owner.user_id and a.revoked_at is null
    and (a.expires_at is null or a.expires_at>pg_catalog.now())
    and r.domain='platform' and r.code='platform_owner'
    and r.scope_type='platform' and a.scope_type='platform' and a.scope_id is null
 );
$$;

create or replace function public.is_system_admin(user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=''
as $$
 select user_id is not null and exists(
  select 1 from platform.user_roles a
  join platform.roles r on r.id=a.role_id
  where a.user_id=is_system_admin.user_id and a.revoked_at is null
    and (a.expires_at is null or a.expires_at>pg_catalog.now())
    and r.domain='platform' and r.code in ('platform_owner','platform_admin')
    and r.scope_type='platform' and a.scope_type='platform' and a.scope_id is null
 );
$$;

create or replace function public.is_account_approved(user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=''
as $$
 select user_id is not null and exists(
  select 1 from platform.profiles p
  where p.user_id=is_account_approved.user_id and p.account_status='approved'
 );
$$;
