begin;

-- P6C1: Conference role/membership is no longer an authorization plane.
-- Canonical authorization is public.require_effective_module_permission().
-- Historical migrations remain immutable; this migration retires the live role-management surface.

-- Remove the child-membership invariant that existed only for the retired Conference role model.
drop trigger if exists conference_members_require_organization_membership on public.conference_members;
drop function if exists public.require_conference_member_organization_membership();

drop trigger if exists organization_members_protect_conference_memberships on public.organization_members;
drop function if exists public.prevent_conference_member_organization_removal();

-- Retire all known browser/internal Conference role-management entry points.
do $$
declare
  target record;
begin
  for target in
    select p.oid::regprocedure as signature
      from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public'
       and p.proname = any(array[
         'get_my_conference_access',
         'list_conference_members',
         'lookup_conference_user_by_email',
         'manage_conference_member',
         'add_conference_manager',
         'remove_conference_manager',
         'device_guarded_get_my_conference_access',
         'device_guarded_get_my_conference_membership',
         'device_guarded_list_conference_members',
         'device_guarded_lookup_conference_user_by_email',
         'device_guarded_manage_conference_member',
         'device_guarded_add_conference_manager',
         'device_guarded_remove_conference_manager'
       ])
  loop
    execute format('drop function %s',target.signature);
  end loop;
end $$;

-- The role-operation ledger has no final-product purpose and old data is disposable.
drop table if exists public.conference_membership_operations;

-- conference_members itself is intentionally not dropped in this migration yet:
-- legacy Conference lock functions still reference is_conference_member()/has_conference_role().
-- P6C1 must cut those lock dependencies to canonical permission/concurrency semantics first,
-- then drop the remaining role table/helpers in the same final branch before promotion.

-- No browser role may regain direct authority over the residual table while lock cutover is pending.
revoke all on table public.conference_members from public, anon, authenticated;

-- Postconditions for the retired management plane.
do $$
declare
  remaining text;
begin
  select p.oid::regprocedure::text into remaining
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public'
     and p.proname = any(array[
       'get_my_conference_access','list_conference_members','lookup_conference_user_by_email',
       'manage_conference_member','add_conference_manager','remove_conference_manager',
       'device_guarded_get_my_conference_access','device_guarded_get_my_conference_membership',
       'device_guarded_list_conference_members','device_guarded_lookup_conference_user_by_email',
       'device_guarded_manage_conference_member','device_guarded_add_conference_manager',
       'device_guarded_remove_conference_manager'
     ])
   limit 1;
  if remaining is not null then
    raise exception 'RETIRED_CONFERENCE_ROLE_FUNCTION_REMAINS: %',remaining using errcode='55000';
  end if;

  if to_regclass('public.conference_membership_operations') is not null then
    raise exception 'RETIRED_CONFERENCE_ROLE_LEDGER_REMAINS' using errcode='55000';
  end if;
end $$;

commit;
