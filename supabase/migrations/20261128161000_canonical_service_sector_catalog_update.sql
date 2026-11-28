-- Canonical, additive service-sector catalog cutover; existing request/member rows and stable sector IDs are preserved.
begin;

-- Keep stable canonical IDs for existing sectors; only labels change.
-- Add the new sector ID to both persisted registration contracts.
alter table reservations.public_registration_requests
  drop constraint if exists public_registration_requests_submitted_service_sector_canonical_check;
alter table reservations.public_registration_request_members
  drop constraint if exists public_registration_request_members_service_sector_canonical_check;

alter table reservations.public_registration_requests
  add constraint public_registration_requests_submitted_service_sector_canonical_check
  check (submitted_service_sector in (
    'widows','widows-daughters','discipleship-primary-prep',
    'discipleship-secondary-university','worship','media',
    'servant-preparation','administration','house-of-prayer','other'
  ));

alter table reservations.public_registration_request_members
  add constraint public_registration_request_members_service_sector_canonical_check
  check (service_sector in (
    'widows','widows-daughters','discipleship-primary-prep',
    'discipleship-secondary-university','worship','media',
    'servant-preparation','administration','house-of-prayer','other'
  ));

-- The public family submit/member-add RPCs validate sector IDs before insert.
-- Extend the existing canonical whitelist in-place; do not introduce a second RPC.
do $$
declare
  f record;
  old_list text := '''widows'',''widows-daughters'',''discipleship-primary-prep'',''discipleship-secondary-university'',''worship'',''media'',''servant-preparation'',''administration'',''other''';
  new_list text := '''widows'',''widows-daughters'',''discipleship-primary-prep'',''discipleship-secondary-university'',''worship'',''media'',''servant-preparation'',''administration'',''house-of-prayer'',''other''';
  definition text;
begin
  for f in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname like 'reservations%'
      and p.prokind='f'
      and p.prosrc like '%widows-daughters%'
      and p.prosrc like '%PUBLIC_REGISTRATION_SERVICE_SECTOR_INVALID%'
  loop
    definition := pg_get_functiondef(f.oid);
    if position(new_list in definition)=0 then
      if position(old_list in definition)=0 then
        raise exception 'CANONICAL_SERVICE_SECTOR_FUNCTION_ANCHOR_MISMATCH: %', f.oid;
      end if;
      execute replace(definition, old_list, new_list);
    end if;
  end loop;
end $$;

commit;
