begin;

drop trigger if exists conference_members_require_organization_membership on public.conference_members;
drop function if exists public.require_conference_member_organization_membership();

drop trigger if exists organization_members_protect_conference_memberships on public.organization_members;
drop function if exists public.prevent_conference_member_organization_removal();

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
         'get_my_conference_access','list_conference_members','lookup_conference_user_by_email',
         'manage_conference_member','add_conference_manager','remove_conference_manager',
         'device_guarded_get_my_conference_access','device_guarded_get_my_conference_membership',
         'device_guarded_list_conference_members','device_guarded_lookup_conference_user_by_email',
         'device_guarded_manage_conference_member','device_guarded_add_conference_manager',
         'device_guarded_remove_conference_manager'
       ])
  loop
    execute format('drop function %s',target.signature);
  end loop;
end $$;

drop table if exists public.conference_membership_operations;

revoke all on table public.conference_members from public, anon, authenticated;

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

commit;;
