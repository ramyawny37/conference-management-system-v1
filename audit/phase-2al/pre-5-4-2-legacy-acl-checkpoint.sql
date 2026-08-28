-- LAB_ONLY_CANONICAL_5_4_2_INCOMING_ACL_CONTRACT
-- NOT PRODUCTION MIGRATION HISTORY
-- NEVER EXECUTE AGAINST PRODUCTION OR DEVELOPMENT
do $lab_acl_pre$
declare mismatch_count integer; six_mismatch_count integer; unexpected_overload_count integer;
begin
  if current_setting('server_version_num')::integer/10000 <> 17
    or inet_server_addr() is null
    or inet_server_addr() not in (inet '127.0.0.1',inet '::1')
    or current_database() !~ '^phase2a[[:alnum:]_]*$'
    or (select system_identifier::text from pg_control_system())='7662742571317219726' then
    raise exception 'LAB_ONLY_5_4_2_ACL_TARGET_REFUSED';
  end if;
  with expected(signature,ep,ea,eu,is_six) as (values
    ('public.list_my_organizations()',false,false,true,false),
    ('public.get_my_organization_access(uuid)',false,false,true,false),
    ('public.list_organization_members(uuid)',false,false,true,false),
    ('public.lookup_organization_candidate_by_email(uuid,text)',false,false,true,false),
    ('public.get_my_conference_access(uuid)',false,false,true,false),
    ('public.list_conference_members(uuid)',false,false,true,false),
    ('public.lookup_conference_user_by_email(uuid,text)',false,false,true,false),
    ('public.get_conference_lock(uuid,uuid)',false,true,true,true),
    ('public.add_organization_member(uuid,uuid,uuid)',false,false,true,false),
    ('public.remove_organization_member(uuid,uuid,uuid)',false,false,true,false),
    ('public.change_organization_role(uuid,uuid,text,uuid)',false,false,true,false),
    ('public.add_conference_manager(uuid,uuid,uuid)',false,false,true,false),
    ('public.remove_conference_manager(uuid,uuid,uuid)',false,false,true,false),
    ('public.create_conference_idempotent(uuid,uuid,text,jsonb)',false,false,true,false),
    ('public.apply_conference_snapshot(uuid,uuid,uuid,bigint,jsonb,text,text)',false,true,true,true),
    ('public.acquire_conference_lock(uuid,uuid,uuid,integer)',false,true,true,true),
    ('public.renew_conference_lock(uuid,uuid,uuid,integer)',false,true,true,true),
    ('public.release_conference_lock(uuid,uuid,uuid)',false,true,true,true),
    ('public.resolve_sync_conflict(uuid,uuid,uuid,uuid,bigint,text,jsonb,text,text)',false,true,true,true)
  ), state as (select *,to_regprocedure(signature) oid from expected), deviations as (
    select *,oid is null missing,
      case when oid is null then null else has_function_privilege('public',oid,'execute') end ap,
      case when oid is null then null else has_function_privilege('anon',oid,'execute') end aa,
      case when oid is null then null else has_function_privilege('authenticated',oid,'execute') end au
    from state
  ) select count(*) filter(where missing or ap is distinct from ep or aa is distinct from ea or au is distinct from eu),
      count(*) filter(where is_six and not missing and ap=false and aa=false and au=true)
    into mismatch_count,six_mismatch_count from deviations;
  if mismatch_count<>6 or six_mismatch_count<>6 then
    raise exception 'LAB_ONLY_5_4_2_ACL_PRECONDITION_MISMATCH total=% six=%',mismatch_count,six_mismatch_count;
  end if;
  select count(*) into unexpected_overload_count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname in ('get_conference_lock','apply_conference_snapshot','acquire_conference_lock',
      'renew_conference_lock','release_conference_lock','resolve_sync_conflict')
    and p.oid<>all(array[
      to_regprocedure('public.get_conference_lock(uuid,uuid)'),
      to_regprocedure('public.apply_conference_snapshot(uuid,uuid,uuid,bigint,jsonb,text,text)'),
      to_regprocedure('public.acquire_conference_lock(uuid,uuid,uuid,integer)'),
      to_regprocedure('public.renew_conference_lock(uuid,uuid,uuid,integer)'),
      to_regprocedure('public.release_conference_lock(uuid,uuid,uuid)'),
      to_regprocedure('public.resolve_sync_conflict(uuid,uuid,uuid,uuid,bigint,text,jsonb,text,text)')
    ]);
  if unexpected_overload_count<>0 then
    raise exception 'LAB_ONLY_5_4_2_ACL_UNEXPECTED_OVERLOADS_%',unexpected_overload_count;
  end if;
end;
$lab_acl_pre$;

grant execute on function public.get_conference_lock(uuid,uuid),
  public.apply_conference_snapshot(uuid,uuid,uuid,bigint,jsonb,text,text),
  public.acquire_conference_lock(uuid,uuid,uuid,integer),
  public.renew_conference_lock(uuid,uuid,uuid,integer),
  public.release_conference_lock(uuid,uuid,uuid),
  public.resolve_sync_conflict(uuid,uuid,uuid,uuid,bigint,text,jsonb,text,text)
to anon;

do $lab_acl_post$
declare mismatch_count integer;
begin
  with expected(signature,ep,ea,eu) as (values
    ('public.list_my_organizations()',false,false,true),
    ('public.get_my_organization_access(uuid)',false,false,true),
    ('public.list_organization_members(uuid)',false,false,true),
    ('public.lookup_organization_candidate_by_email(uuid,text)',false,false,true),
    ('public.get_my_conference_access(uuid)',false,false,true),
    ('public.list_conference_members(uuid)',false,false,true),
    ('public.lookup_conference_user_by_email(uuid,text)',false,false,true),
    ('public.get_conference_lock(uuid,uuid)',false,true,true),
    ('public.add_organization_member(uuid,uuid,uuid)',false,false,true),
    ('public.remove_organization_member(uuid,uuid,uuid)',false,false,true),
    ('public.change_organization_role(uuid,uuid,text,uuid)',false,false,true),
    ('public.add_conference_manager(uuid,uuid,uuid)',false,false,true),
    ('public.remove_conference_manager(uuid,uuid,uuid)',false,false,true),
    ('public.create_conference_idempotent(uuid,uuid,text,jsonb)',false,false,true),
    ('public.apply_conference_snapshot(uuid,uuid,uuid,bigint,jsonb,text,text)',false,true,true),
    ('public.acquire_conference_lock(uuid,uuid,uuid,integer)',false,true,true),
    ('public.renew_conference_lock(uuid,uuid,uuid,integer)',false,true,true),
    ('public.release_conference_lock(uuid,uuid,uuid)',false,true,true),
    ('public.resolve_sync_conflict(uuid,uuid,uuid,uuid,bigint,text,jsonb,text,text)',false,true,true)
  ), state as (select *,to_regprocedure(signature) oid from expected)
  select count(*) into mismatch_count from state where oid is null
    or has_function_privilege('public',oid,'execute') is distinct from ep
    or has_function_privilege('anon',oid,'execute') is distinct from ea
    or has_function_privilege('authenticated',oid,'execute') is distinct from eu;
  if mismatch_count<>0 then raise exception 'LAB_ONLY_5_4_2_ACL_POSTCONDITION_MISMATCH_%',mismatch_count; end if;
end;
$lab_acl_post$;
