-- Generated dedicated Production stream migration.
-- Project: mpezfbvcdfxpgflehuot; Development ref is forbidden: gppwltrifgfxrkzvvxoe.
-- Semantic release: grant-reconciliation; intentional delta: PRODUCTION_OPTIONAL_HISTORICAL_RLS_AUTO_ENABLE_ABSENCE.
do $production_gate$
declare latest record;
begin
  if current_setting('server_version_num')::integer<170000
    or current_setting('server_version_num')::integer>=180000 then
    raise exception 'PRODUCTION_STREAM_POSTGRES_17_REQUIRED';
  end if;
  select version,name into latest from supabase_migrations.schema_migrations
    order by version desc limit 1;
  if latest.version is distinct from '20260828144000'
    or latest.name is distinct from 'production_pending_device_operation_purpose_variable_reconciliation_6_20_9' then
    raise exception 'PRODUCTION_STREAM_EXACT_PREDECESSOR_REQUIRED';
  end if;
  if (select count(*)<>1 or coalesce(bool_or(enabled),true)
      from public.webauthn_privileged_device_feature) then
    raise exception 'PRODUCTION_STREAM_WEBAUTHN_MUST_BE_DISABLED';
  end if;
  if (select count(*)<>1 or coalesce(bool_or(enforcement_enabled),true)
      from public.device_authorization_enforcement) then
    raise exception 'PRODUCTION_STREAM_DEVICE_ENFORCEMENT_MUST_BE_DISABLED';
  end if;
end;
$production_gate$;
-- Production evidence (PostgreSQL 17.6, project mpezfbvcdfxpgflehuot) proves this
-- repository-undefined historical helper is absent. If it unexpectedly exists later,
-- reconcile only its exact zero-argument signature without creating or replacing it.
do $production_optional_historical_grant$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    execute 'revoke execute on function public.rls_auto_enable() from public, anon, authenticated';
  end if;
end;
$production_optional_historical_grant$;
revoke execute on function public.enforce_launch_conference_member_contract() from public, anon, authenticated;
revoke execute on function public.prevent_null_conference_organization() from public, anon, authenticated;

revoke execute on function public.acquire_conference_lock(uuid, uuid, uuid, integer) from anon;
revoke execute on function public.renew_conference_lock(uuid, uuid, uuid, integer) from anon;
revoke execute on function public.release_conference_lock(uuid, uuid, uuid) from anon;
revoke execute on function public.get_conference_lock(uuid, uuid) from anon;
revoke execute on function public.get_conference_section_lock(uuid, text, uuid) from anon;
revoke execute on function public.is_conference_member(uuid) from anon;
revoke execute on function public.has_conference_role(uuid, text[]) from anon;
revoke execute on function public.is_conference_owner(uuid) from anon;

do $production_post$
begin
  if (select count(*)<>1 or coalesce(bool_or(enabled),true)
      from public.webauthn_privileged_device_feature)
    or (select count(*)<>1 or coalesce(bool_or(enforcement_enabled),true)
      from public.device_authorization_enforcement) then
    raise exception 'PRODUCTION_STREAM_INERT_POSTCONDITION_FAILED';
  end if;
end;
$production_post$;
