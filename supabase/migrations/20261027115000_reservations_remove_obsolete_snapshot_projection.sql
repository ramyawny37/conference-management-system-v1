begin;
drop function reservations_private.project_booking_to_conference(uuid,uuid,jsonb);
do $$
begin
 if exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('reservations','reservations_private') and p.prokind='f'
    and pg_get_functiondef(p.oid) like '%conference_snapshots%'
 ) then raise exception 'RESERVATIONS_LEGACY_SNAPSHOT_REMAINS' using errcode='55000'; end if;
end $$;
commit;
