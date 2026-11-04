-- Canonical personal profile fields for the shared people directory.
-- Reservation participant columns remain historical booking snapshots.
-- No experimental booking data is migrated or overwritten.
begin;

alter table platform.people
  add column if not exists governorate text,
  add column if not exists city_or_village text,
  add column if not exists service_sector text,
  add column if not exists service_sector_other text;

comment on column platform.people.governorate is 'Current personal governorate; booking participant values remain historical snapshots.';
comment on column platform.people.city_or_village is 'Current personal city or village.';
comment on column platform.people.service_sector is 'Current personal service sector.';
comment on column platform.people.service_sector_other is 'Current personal service sector detail when applicable.';

commit;
;
