begin;

-- P6I-C1C: linked Conferences are owned by the canonical domain tables.  The
-- whole-document snapshot ledger and all of its data are intentionally retired.
drop function if exists public.device_guarded_resolve_sync_conflict(uuid,uuid,uuid,uuid,bigint,text,jsonb,text,text);
drop function if exists public.device_guarded_list_sync_conflicts(uuid,uuid,text,integer);
drop function if exists public.device_guarded_get_sync_conflict(uuid,uuid);
drop function if exists public.device_guarded_apply_conference_snapshot(uuid,uuid,uuid,bigint,jsonb,text,text);
drop function if exists public.device_guarded_download_conference_snapshot(uuid,uuid);
drop function if exists public.device_guarded_get_conference_snapshot_metadata(uuid,uuid);
drop function if exists public.resolve_sync_conflict(uuid,uuid,uuid,uuid,bigint,text,jsonb,text,text);
drop function if exists public.apply_conference_snapshot(uuid,uuid,uuid,bigint,jsonb,text,text);

-- These tables have no remaining canonical/non-snapshot consumer.  CASCADE is
-- deliberate: it removes snapshot-only policies, triggers, indexes and grants.
drop table if exists public.conference_snapshot_guard_intents cascade;
drop table if exists public.sync_conflicts cascade;
drop table if exists public.sync_operations cascade;

do $$
begin
  if exists (
    select 1
      from pg_publication_rel pr
      join pg_class c on c.oid=pr.prrelid
      join pg_namespace n on n.oid=c.relnamespace
      join pg_publication p on p.oid=pr.prpubid
     where p.pubname='supabase_realtime'
       and n.nspname='public'
       and c.relname='conference_snapshots'
  ) then
    alter publication supabase_realtime drop table public.conference_snapshots;
  end if;
end;
$$;

drop table if exists public.conference_snapshots cascade;

-- The canonical domains still use conference.sync.write as an authorization
-- capability.  Whole-document conflict resolution has no surviving consumer.
do $$
begin
  if to_regclass('public.module_permission_catalog') is not null then
    update public.module_permission_catalog
       set status='retired',
           retired_at=statement_timestamp(),
           catalog_version=catalog_version+1
     where permission_key='conference.conflict.resolve'
       and status='active';
  end if;
end;
$$;

do $$
begin
  if to_regclass('public.conference_snapshots') is not null
    or to_regclass('public.sync_operations') is not null
    or to_regclass('public.sync_conflicts') is not null
    or to_regclass('public.conference_snapshot_guard_intents') is not null then
    raise exception 'C1C_SNAPSHOT_TABLE_RETIREMENT_INCOMPLETE';
  end if;
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname in (
       'apply_conference_snapshot','resolve_sync_conflict',
       'device_guarded_apply_conference_snapshot',
       'device_guarded_download_conference_snapshot',
       'device_guarded_get_conference_snapshot_metadata',
       'device_guarded_get_sync_conflict',
       'device_guarded_list_sync_conflicts',
       'device_guarded_resolve_sync_conflict'
     )
  ) then
    raise exception 'C1C_SNAPSHOT_FUNCTION_RETIREMENT_INCOMPLETE';
  end if;
end;
$$;

commit;
