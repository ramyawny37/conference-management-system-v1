begin;

-- Conference authorization is exclusively owned by canonical Platform permissions.
-- Historical Conference role-membership data is disposable; no compatibility path remains.

do $$
declare
  offender text;
begin
  select p.oid::regprocedure::text into offender
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.prokind='f'
    and p.proname not in ('is_conference_member','has_conference_role')
    and pg_get_functiondef(p.oid) ~* 'conference_members|is_conference_member|has_conference_role'
  order by p.oid::regprocedure::text
  limit 1;

  if offender is not null then
    raise exception 'CONFERENCE_MEMBERSHIP_CONSUMER_REMAINS: %',offender using errcode='55000';
  end if;
end $$;

-- These policies are the final RLS consumers of the retired membership helpers.
-- Canonical Platform permissions own Conference authorization; no replacement policy is created.
drop policy if exists conferences_select_member on public.conferences;
drop policy if exists conference_members_select_member on public.conference_members;

do $$
declare
  target record;
begin
  for target in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in ('is_conference_member','has_conference_role')
  loop
    execute format('drop function %s',target.signature);
  end loop;
end $$;

-- Deliberately no CASCADE: any unexpected live dependency must stop the cutover.
drop table if exists public.conference_members;

do $$
declare
  offender text;
begin
  if to_regclass('public.conference_members') is not null then
    raise exception 'CONFERENCE_MEMBERS_TABLE_REMAINS' using errcode='55000';
  end if;

  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('is_conference_member','has_conference_role')
  ) then
    raise exception 'CONFERENCE_MEMBERSHIP_HELPER_REMAINS' using errcode='55000';
  end if;

  select p.oid::regprocedure::text into offender
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.prokind='f'
    and pg_get_functiondef(p.oid) ~* 'conference_members|is_conference_member|has_conference_role'
  order by p.oid::regprocedure::text
  limit 1;

  if offender is not null then
    raise exception 'CONFERENCE_MEMBERSHIP_RUNTIME_REFERENCE_REMAINS: %',offender using errcode='55000';
  end if;
end $$;

commit;
