begin;

-- P6C1: keep the lock mechanism only as concurrency control.
-- It MUST NOT decide authority from Conference membership roles.
-- Authority comes exclusively from the canonical Platform permission resolver.

create or replace function public.require_conference_section_lock_writer(
  p_conference_id uuid,
  p_actor_device_id uuid,
  p_section text default null
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public as $$
declare
  authority jsonb;
  actor_id uuid;
  normalized_section text := lower(trim(coalesce(p_section,'')));
  permission_key text;
begin
  if p_conference_id is null or p_actor_device_id is null then
    raise exception 'INVALID_CONFERENCE_LOCK_AUTHORIZATION_ARGUMENTS' using errcode='22023';
  end if;

  -- The current live section-lock consumer is accommodation. Whole-conference
  -- locks are synchronization concurrency and use conference.sync.write.
  permission_key := case
    when normalized_section = 'accommodation' then 'conference.accommodation.manage'
    when normalized_section = '' or normalized_section = 'conference' then 'conference.sync.write'
    else null
  end;
  if permission_key is null then
    raise exception 'UNMAPPED_CONFERENCE_LOCK_SECTION: %',normalized_section using errcode='42501';
  end if;

  authority := public.require_effective_module_permission(
    p_actor_device_id,
    'conference',
    permission_key,
    'conference',
    p_conference_id::text
  );
  actor_id := nullif(authority->>'actorUserId','')::uuid;
  if actor_id is null then
    raise exception 'CANONICAL_CONFERENCE_LOCK_AUTHORITY_INVALID' using errcode='42501';
  end if;
  return actor_id;
end;
$$;

-- Rebuild the three section-lock RPCs so every acquire/renew/release authorization
-- check carries the exact section into the canonical resolver.
do $$
declare
  fn regprocedure;
  definition text;
begin
  foreach fn in array array[
    to_regprocedure('public.acquire_conference_section_lock(uuid,text,uuid,uuid,integer)'),
    to_regprocedure('public.renew_conference_section_lock(uuid,text,uuid,uuid,integer)'),
    to_regprocedure('public.release_conference_section_lock(uuid,text,uuid,uuid)')
  ] loop
    if fn is null then
      raise exception 'CONFERENCE_SECTION_LOCK_FUNCTION_MISSING' using errcode='55000';
    end if;
    definition := pg_get_functiondef(fn);
    definition := replace(
      definition,
      'p_conference_id,p_device_id\n  )',
      'p_conference_id,p_device_id,normalized_section\n  )'
    );
    if definition = pg_get_functiondef(fn) then
      -- tolerate formatting emitted without the historical newline layout
      definition := replace(
        definition,
        'p_conference_id,p_device_id)',
        'p_conference_id,p_device_id,normalized_section)'
      );
    end if;
    if definition = pg_get_functiondef(fn) then
      raise exception 'CONFERENCE_SECTION_LOCK_AUTH_CALL_NOT_REWRITTEN: %',fn using errcode='55000';
    end if;
    execute definition;
  end loop;
end $$;

-- Whole-conference lock RPCs are retained only for sync concurrency. Replace
-- their legacy membership/role helper calls with canonical sync.write checks.
-- We do not alter token, TTL, ownership, row-lock, or expiry semantics.
do $$
declare
  fn regprocedure;
  definition text;
  original text;
begin
  foreach fn in array array[
    to_regprocedure('public.acquire_conference_lock(uuid,uuid,uuid,integer)'),
    to_regprocedure('public.renew_conference_lock(uuid,uuid,uuid,integer)'),
    to_regprocedure('public.release_conference_lock(uuid,uuid,uuid)')
  ] loop
    if fn is null then
      continue;
    end if;
    original := pg_get_functiondef(fn);
    definition := original;

    -- Historical functions call is_conference_member()/has_conference_role().
    -- Replace those boolean guards with a canonical authorization expression.
    definition := regexp_replace(
      definition,
      'if[[:space:]]+not[[:space:]]+public[.]is_conference_member[(]p_conference_id[)][[:space:]]+then[[:space:]]+raise[[:space:]]+exception[^;]*;[[:space:]]+end[[:space:]]+if;',
      'perform public.require_effective_module_permission(p_device_id,''conference'',''conference.sync.write'',''conference'',p_conference_id::text);',
      'gi'
    );
    definition := regexp_replace(
      definition,
      'if[[:space:]]+not[[:space:]]+public[.]has_conference_role[(]p_conference_id[^;]*?then[[:space:]]+raise[[:space:]]+exception[^;]*;[[:space:]]+end[[:space:]]+if;',
      'perform public.require_effective_module_permission(p_device_id,''conference'',''conference.sync.write'',''conference'',p_conference_id::text);',
      'gi'
    );

    if definition ~* 'is_conference_member|has_conference_role' then
      raise exception 'WHOLE_CONFERENCE_LOCK_LEGACY_AUTHORITY_REMAINS: %',fn using errcode='55000';
    end if;
    if definition <> original then
      execute definition;
    end if;
  end loop;
end $$;

-- Postconditions: locks may remain as concurrency primitives, but no lock writer
-- authority may consult Conference membership roles.
do $$
declare
  offender text;
begin
  select p.oid::regprocedure::text into offender
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname in (
      'require_conference_section_lock_writer',
      'acquire_conference_section_lock','renew_conference_section_lock','release_conference_section_lock',
      'acquire_conference_lock','renew_conference_lock','release_conference_lock'
    )
    and pg_get_functiondef(p.oid) ~* 'conference_members|is_conference_member|has_conference_role'
  order by p.oid::regprocedure::text limit 1;
  if offender is not null then
    raise exception 'CONFERENCE_LOCK_ROLE_AUTHORITY_REMAINS: %',offender using errcode='55000';
  end if;

  if position('require_effective_module_permission' in pg_get_functiondef(
    to_regprocedure('public.require_conference_section_lock_writer(uuid,uuid,text)')
  ))=0 then
    raise exception 'CANONICAL_SECTION_LOCK_AUTHORITY_MISSING' using errcode='55000';
  end if;
end $$;

commit;
