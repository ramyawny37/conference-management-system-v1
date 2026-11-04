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

-- Keep the latest device-guarded lock semantics deterministic while passing
-- the normalized section to the canonical permission resolver.
create or replace function public.acquire_conference_section_lock(
  p_conference_id uuid,
  p_section text,
  p_device_id uuid,
  p_lock_token uuid,
  p_ttl_seconds integer default 120
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public as $$
declare
  current_user_id uuid;
  effective_ttl integer := coalesce(p_ttl_seconds,120);
  normalized_section text := lower(trim(coalesce(p_section,'')));
  current_lock public.conference_locks%rowtype;
  server_now timestamptz := clock_timestamp();
  new_expiry timestamptz;
begin
  if p_conference_id is null or p_device_id is null or p_lock_token is null
    or normalized_section !~ '^[a-z][a-z0-9_]{0,31}$'
    or effective_ttl < 30 or effective_ttl > 300 then
    raise exception 'INVALID_CONFERENCE_SECTION_LOCK_ARGUMENTS' using errcode = '22023';
  end if;

  current_user_id := public.require_conference_section_lock_writer(
    p_conference_id,p_device_id,normalized_section
  );

  perform 1 from public.conferences as conferences
   where conferences.id = p_conference_id for update;
  if not found then
    raise exception 'CONFERENCE_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform public.require_conference_section_lock_writer(
    p_conference_id,p_device_id,normalized_section
  );

  select * into current_lock from public.conference_locks as locks
   where locks.conference_id = p_conference_id
     and locks.section = normalized_section for update;
  new_expiry := server_now + make_interval(secs => effective_ttl);

  if not found then
    insert into public.conference_locks(
      conference_id,section,user_id,device_id,lock_token,
      acquired_at,expires_at,last_renewed_at,created_at
    ) values(
      p_conference_id,normalized_section,current_user_id,p_device_id,p_lock_token,
      server_now,new_expiry,server_now,server_now
    );
    return jsonb_build_object(
      'success',true,'status','acquired','conferenceId',p_conference_id,
      'section',normalized_section,'lockToken',p_lock_token,'owned',true,
      'userId',current_user_id,'deviceId',p_device_id,'acquiredAt',server_now,
      'expiresAt',new_expiry,'lastRenewedAt',server_now,'serverNow',server_now,
      'isExpired',false
    );
  end if;

  if current_lock.expires_at <= server_now then
    update public.conference_locks
       set user_id=current_user_id,device_id=p_device_id,lock_token=p_lock_token,
           acquired_at=server_now,expires_at=new_expiry,
           last_renewed_at=server_now,created_at=server_now
     where conference_id=p_conference_id and section=normalized_section;
    return jsonb_build_object(
      'success',true,'status','acquired','conferenceId',p_conference_id,
      'section',normalized_section,'lockToken',p_lock_token,'owned',true,
      'userId',current_user_id,'deviceId',p_device_id,'acquiredAt',server_now,
      'expiresAt',new_expiry,'lastRenewedAt',server_now,'serverNow',server_now,
      'isExpired',false
    );
  end if;

  if current_lock.user_id=current_user_id and current_lock.device_id=p_device_id then
    return jsonb_build_object(
      'success',true,'status','already_owned','conferenceId',p_conference_id,
      'section',normalized_section,'lockToken',current_lock.lock_token,'owned',true,
      'userId',current_lock.user_id,'deviceId',current_lock.device_id,
      'acquiredAt',current_lock.acquired_at,'expiresAt',current_lock.expires_at,
      'lastRenewedAt',current_lock.last_renewed_at,'serverNow',server_now,
      'isExpired',false
    );
  end if;

  return jsonb_build_object(
    'success',true,'status','locked','errorCode','LOCK_NOT_OWNED',
    'conferenceId',p_conference_id,'section',normalized_section,'owned',false,
    'userId',current_lock.user_id,'deviceId',current_lock.device_id,
    'acquiredAt',current_lock.acquired_at,'expiresAt',current_lock.expires_at,
    'lastRenewedAt',current_lock.last_renewed_at,'serverNow',server_now,
    'isExpired',false
  );
end;
$$;

create or replace function public.renew_conference_section_lock(
  p_conference_id uuid,p_section text,p_device_id uuid,p_lock_token uuid,
  p_ttl_seconds integer default 120
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public as $$
declare
  current_user_id uuid;
  effective_ttl integer := coalesce(p_ttl_seconds,120);
  normalized_section text := lower(trim(coalesce(p_section,'')));
  current_lock public.conference_locks%rowtype;
  lock_found boolean;
  server_now timestamptz := clock_timestamp();
  new_expiry timestamptz;
begin
  if p_conference_id is null or p_device_id is null or p_lock_token is null
    or normalized_section !~ '^[a-z][a-z0-9_]{0,31}$'
    or effective_ttl < 30 or effective_ttl > 300 then
    raise exception 'INVALID_CONFERENCE_SECTION_LOCK_ARGUMENTS' using errcode = '22023';
  end if;

  current_user_id := public.require_conference_section_lock_writer(
    p_conference_id,p_device_id,normalized_section
  );

  select * into current_lock from public.conference_locks as locks
   where locks.conference_id=p_conference_id
     and locks.section=normalized_section for update;
  lock_found := found;

  perform public.require_conference_section_lock_writer(
    p_conference_id,p_device_id,normalized_section
  );

  if not lock_found then
    return jsonb_build_object(
      'success',true,'status','not_found','errorCode','LOCK_NOT_OWNED',
      'conferenceId',p_conference_id,'section',normalized_section,
      'owned',false,'serverNow',server_now,'isExpired',false
    );
  end if;
  if current_lock.expires_at<=server_now then
    return jsonb_build_object(
      'success',true,'status','expired','errorCode','LOCK_EXPIRED',
      'conferenceId',p_conference_id,'section',normalized_section,
      'owned',false,'expiresAt',current_lock.expires_at,
      'lastRenewedAt',current_lock.last_renewed_at,'serverNow',server_now,
      'isExpired',true
    );
  end if;
  if current_lock.user_id<>current_user_id or current_lock.device_id<>p_device_id then
    return jsonb_build_object(
      'success',true,'status','not_owner','errorCode','LOCK_NOT_OWNED',
      'conferenceId',p_conference_id,'section',normalized_section,
      'owned',false,'expiresAt',current_lock.expires_at,
      'lastRenewedAt',current_lock.last_renewed_at,'serverNow',server_now,
      'isExpired',false
    );
  end if;
  if current_lock.lock_token<>p_lock_token then
    return jsonb_build_object(
      'success',true,'status','not_owner','errorCode','LOCK_TOKEN_MISMATCH',
      'conferenceId',p_conference_id,'section',normalized_section,
      'owned',false,'expiresAt',current_lock.expires_at,
      'lastRenewedAt',current_lock.last_renewed_at,'serverNow',server_now,
      'isExpired',false
    );
  end if;

  new_expiry:=server_now+make_interval(secs=>effective_ttl);
  update public.conference_locks
     set expires_at=new_expiry,last_renewed_at=server_now
   where conference_id=p_conference_id and section=normalized_section;
  return jsonb_build_object(
    'success',true,'status','renewed','conferenceId',p_conference_id,
    'section',normalized_section,'lockToken',p_lock_token,'owned',true,
    'userId',current_user_id,'deviceId',p_device_id,
    'acquiredAt',current_lock.acquired_at,'expiresAt',new_expiry,
    'lastRenewedAt',server_now,'serverNow',server_now,'isExpired',false
  );
end;
$$;

create or replace function public.release_conference_section_lock(
  p_conference_id uuid,p_section text,p_device_id uuid,p_lock_token uuid
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public as $$
declare
  current_user_id uuid;
  normalized_section text := lower(trim(coalesce(p_section,'')));
  current_lock public.conference_locks%rowtype;
  lock_found boolean;
  server_now timestamptz := clock_timestamp();
begin
  if p_conference_id is null or p_device_id is null or p_lock_token is null
    or normalized_section !~ '^[a-z][a-z0-9_]{0,31}$' then
    raise exception 'INVALID_CONFERENCE_SECTION_LOCK_ARGUMENTS' using errcode = '22023';
  end if;

  current_user_id := public.require_conference_section_lock_writer(
    p_conference_id,p_device_id,normalized_section
  );

  select * into current_lock from public.conference_locks as locks
   where locks.conference_id=p_conference_id
     and locks.section=normalized_section for update;
  lock_found := found;

  perform public.require_conference_section_lock_writer(
    p_conference_id,p_device_id,normalized_section
  );

  if not lock_found then
    return jsonb_build_object(
      'success',true,'status','not_found','errorCode','LOCK_NOT_OWNED',
      'conferenceId',p_conference_id,'section',normalized_section,
      'owned',false,'serverNow',server_now
    );
  end if;
  if current_lock.user_id<>current_user_id or current_lock.device_id<>p_device_id then
    return jsonb_build_object(
      'success',true,'status','not_owner','errorCode','LOCK_NOT_OWNED',
      'conferenceId',p_conference_id,'section',normalized_section,
      'owned',false,'serverNow',server_now
    );
  end if;
  if current_lock.lock_token<>p_lock_token then
    return jsonb_build_object(
      'success',true,'status','not_owner','errorCode','LOCK_TOKEN_MISMATCH',
      'conferenceId',p_conference_id,'section',normalized_section,
      'owned',false,'serverNow',server_now
    );
  end if;

  delete from public.conference_locks
   where conference_id=p_conference_id and section=normalized_section;
  return jsonb_build_object(
    'success',true,'status','released','conferenceId',p_conference_id,
    'section',normalized_section,'lockToken',p_lock_token,'owned',false,
    'serverNow',server_now
  );
end;
$$;

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

revoke all on function public.require_conference_section_lock_writer(uuid,uuid,text)
  from public,anon,authenticated;
revoke all on function public.acquire_conference_section_lock(uuid,text,uuid,uuid,integer)
  from public,anon;
revoke all on function public.renew_conference_section_lock(uuid,text,uuid,uuid,integer)
  from public,anon;
revoke all on function public.release_conference_section_lock(uuid,text,uuid,uuid)
  from public,anon;
revoke all on function public.get_conference_section_lock(uuid,text,uuid)
  from public,anon;
grant execute on function public.acquire_conference_section_lock(uuid,text,uuid,uuid,integer)
  to authenticated;
grant execute on function public.renew_conference_section_lock(uuid,text,uuid,uuid,integer)
  to authenticated;
grant execute on function public.release_conference_section_lock(uuid,text,uuid,uuid)
  to authenticated;
grant execute on function public.get_conference_section_lock(uuid,text,uuid)
  to authenticated;

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
