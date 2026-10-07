begin;
-- Organization-free Conference/Reservations schema cutover. Runtime function
-- replacements are installed in the immediately following migration.
drop trigger if exists conferences_require_organization_on_insert on public.conferences;
drop function if exists public.prevent_null_conference_organization();

alter table reservations.events
 drop constraint if exists reservations_events_conference_organization_fk,
 drop constraint if exists reservations_events_scope_type_check,
 drop constraint if exists events_organization_id_id_key;
alter table reservations.bookings
 drop constraint if exists bookings_organization_id_booking_number_key,
 drop constraint if exists bookings_organization_id_id_key;
alter table reservations.booking_types
 drop constraint if exists booking_types_organization_id_event_id_id_key,
 drop constraint if exists booking_types_organization_id_id_key;
alter table reservations.event_periods
 drop constraint if exists event_periods_organization_id_event_id_id_key,
 drop constraint if exists event_periods_organization_id_id_key;
alter table reservations.attendance_records drop constraint if exists attendance_records_organization_id_id_key;
alter table reservations.operational_reviews drop constraint if exists operational_reviews_organization_id_id_key;
alter table reservations.participants drop constraint if exists participants_organization_id_id_key;
alter table reservations.payments drop constraint if exists payments_organization_id_id_key;
drop index if exists reservations.reservations_events_list_idx;
drop index if exists reservations.reservations_bookings_list_idx;

alter table reservations.events
 add constraint reservations_events_scope_type_check check(
   (scope_type='conference' and conference_id is not null and scope_partition_id=conference_id)
   or (scope_type='standalone' and conference_id is null)
 ),
 add constraint reservations_events_conference_fk
   foreign key(conference_id) references public.conferences(id) on delete restrict;

alter table reservations.attendance_records drop column if exists organization_id;
alter table reservations.booking_number_counters drop column if exists organization_id;
alter table reservations.booking_types drop column if exists organization_id;
alter table reservations.bookings drop column if exists organization_id;
alter table reservations.event_periods drop column if exists organization_id;
alter table reservations.events drop column if exists organization_id;
alter table reservations.operational_reviews drop column if exists organization_id;
alter table reservations.operations drop column if exists organization_id;
alter table reservations.participants drop column if exists organization_id;
alter table reservations.payments drop column if exists organization_id;
alter table reservations.scope_partition_links drop column if exists organization_id;

alter table public.conferences
 drop constraint if exists conferences_id_organization_unique,
 drop constraint if exists conferences_organization_id_fkey,
 drop column if exists organization_id;
commit;
