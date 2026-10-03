begin;

-- Keep Conference locks only as concurrency control. Authorization comes
-- exclusively from the canonical Platform permission resolver.
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

  permission_key := case
    when normalized_section = 'accommodation' then 'conference.accommodation.manage'
    when normalized_section = '' or normalized_section = 'conference' then 'conference.sync.write'
    else null
  end;
  if permission_key is null then
    raise exception 'UNMAPPED_CONFERENCE_LOCK_SECTION: %',normalized_section using errcode='42501';
  end if;

  authority := public.require_effective_module_permission(
    p_actor_device_id,'conference',permission_key,'conference',p_conference_id::text
  );
  actor_id := nullif(authority->>'actorUserId','')::uuid;
  if actor_id is null then
    raise exception 'CANONICAL_CONFERENCE_LOCK_AUTHORITY_INVALID' using errcode='42501';
  end if;
  return actor_id;
end;
$$;

-- Existing guarded acquire/renew/release functions already centralize writer
-- authorization through require_conference_section_lock_writer(). Carry the
-- exact section into that resolver instead of consulting Conference roles.
do $$
declare
  fn regprocedure;
  definition text;
  original text;
begin
  foreach fn in array array[
    to_regprocedure('public.acquire_conference_section_lock(uuid,text,uuid,uuid,integer)'),
    to_regprocedure('public.renew_conference_section_lock(uuid,text,uuid,uuid,integer)'),
    to_regprocedure('public.release_conference_section_lock(uuid,text,uuid,uuid)')
  ] loop
    if fn is null then
      raise exception 'CONFERENCE_SECTION_LOCK_FUNCTION_MISSING' using errcode='55000';
    end if;
    original := pg_get_functiondef(fn);
    definition := replace(
      original,
      'p_conference_id,p_device_id\n  )',
      'p_conference_id,p_device_id,normalized_section\n  )'
    );
    if definition = original then
      definition := replace(
        original,
        'p_conference_id,p_device_id)',
        'p_conference_id,p_device_id,normalized_section)'
      );
    end if;
    if definition = original then
      raise exception 'CONFERENCE_SECTION_LOCK_AUTH_CALL_NOT_REWRITTEN: %',fn using errcode='55000';
    end if;
    execute definition;
  end loop;
end $$;

-- The historical read RPC was not included in the later device-guard rewrite
-- and still consulted is_conference_member(). Replace it explicitly.
create or replace function public.get_conference_section_lock(
  p_conference_id uuid,p_section text,p_device_id uuid
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public as $$
declare
  current_user_id uuid;
  normalized_section text := lower(trim(coalesce(p_section,'')));
  current_lock public.conference_locks%rowtype;
  server_now timestamptz := clock_timestamp();
  owned_by_requester boolean;
begin
  if p_conference_id is null or p_device_id is null
    or normalized_section !~ '^[a-z][a-z0-9_]{0,31}$' then
    raise exception 'INVALID_CONFERENCE_SECTION_LOCK_ARGUMENTS' using errcode='22023';
  end if;

  current_user_id := public.require_conference_section_lock_writer(
    p_conference_id,p_device_id,normalized_section
  );

  select * into current_lock
  from public.conference_locks as locks
  where locks.conference_id=p_conference_id and locks.section=normalized_section;

  if not found then
    return jsonb_build_object(
      'success',true,'status','not_found','conferenceId',p_conference_id,
      'section',normalized_section,'locked',false,'owned',false,
      'serverNow',server_now,'isExpired',false
    );
  end if;

  owned_by_requester := current_lock.user_id=current_user_id
    and current_lock.device_id=p_device_id;
  return jsonb_strip_nulls(jsonb_build_object(
    'success',true,
    'status',case when current_lock.expires_at<=server_now then 'not_found' else 'locked' end,
    'conferenceId',p_conference_id,'section',normalized_section,
    'locked',current_lock.expires_at>server_now,
    'owned',owned_by_requester and current_lock.expires_at>server_now,
    'lockToken',case when owned_by_requester then current_lock.lock_token else null end,
    'userId',current_lock.user_id,'deviceId',current_lock.device_id,
    'acquiredAt',current_lock.acquired_at,'expiresAt',current_lock.expires_at,
    'lastRenewedAt',current_lock.last_renewed_at,'serverNow',server_now,
    'isExpired',current_lock.expires_at<=server_now
  ));
end;
$$;

-- Whole-conference RPCs are SQL wrappers around section='conference'. They
-- therefore inherit conference.sync.write from the canonical resolver.
-- Verify they contain no independent legacy role authority.
do $$
declare
  fn regprocedure;
  definition text;
begin
  foreach fn in array array[
    to_regprocedure('public.acquire_conference_lock(uuid,uuid,uuid,integer)'),
    to_regprocedure('public.renew_conference_lock(uuid,uuid,uuid,integer)'),
    to_regprocedure('public.release_conference_lock(uuid,uuid,uuid)'),
    to_regprocedure('public.get_conference_lock(uuid,uuid)')
  ] loop
    if fn is null then continue; end if;
    definition := pg_get_functiondef(fn);
    if definition ~* 'conference_members|is_conference_member|has_conference_role' then
      raise exception 'WHOLE_CONFERENCE_LOCK_LEGACY_AUTHORITY_REMAINS: %',fn using errcode='55000';
    end if;
  end loop;
end $$;

-- Postconditions: no Conference lock RPC may consult Conference membership roles.
do $$
declare
  offender text;
begin
  select p.oid::regprocedure::text into offender
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname in (
      'require_conference_section_lock_writer',
      'acquire_conference_section_lock','renew_conference_section_lock',
      'release_conference_section_lock','get_conference_section_lock',
      'acquire_conference_lock','renew_conference_lock',
      'release_conference_lock','get_conference_lock'
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
