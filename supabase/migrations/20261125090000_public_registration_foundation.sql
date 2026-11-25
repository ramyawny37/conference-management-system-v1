begin;

-- PR1 Public Registration foundation.
-- This migration deliberately creates no public RPC and grants no client role
-- table access. PR2/PR3 will expose narrow server operations only.

do $foundation$
begin
  if to_regclass('reservations.events') is null
     or to_regclass('reservations.booking_types') is null
     or to_regclass('reservations.bookings') is null
     or to_regclass('platform.people') is null then
    raise exception 'PUBLIC_REGISTRATION_CANONICAL_FOUNDATION_REQUIRED' using errcode='55000';
  end if;
end
$foundation$;

create table reservations.public_registration_channels(
  id uuid primary key default extensions.gen_random_uuid(),
  event_id uuid not null references reservations.events(id) on delete restrict,
  public_id uuid not null default extensions.gen_random_uuid(),
  enabled boolean not null default false,
  registration_mode text not null default 'approval_required'
    check(registration_mode in('approval_required','auto_approve')),
  full_policy text not null default 'reject'
    check(full_policy in('reject','waitlist')),
  opens_at timestamptz,
  closes_at timestamptz,
  revision bigint not null default 1 check(revision>0),
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  created_by uuid not null references platform.profiles(user_id),
  updated_by uuid not null references platform.profiles(user_id),
  unique(event_id),
  unique(public_id),
  unique(id,event_id),
  check(opens_at is null or closes_at is null or closes_at>opens_at),
  check(updated_at>=created_at)
);

-- booking_types.id is globally unique already; this composite unique index restores a
-- relational event/type key without creating a second booking-type authority.
create unique index if not exists reservations_booking_types_event_id_id_uidx
  on reservations.booking_types(event_id,id);

create table reservations.public_registration_requests(
  id uuid primary key default extensions.gen_random_uuid(),
  channel_id uuid not null,
  event_id uuid not null,
  submit_operation_id uuid not null,
  request_reference text not null
    check(request_reference=btrim(request_reference) and char_length(request_reference) between 6 and 40),
  tracking_secret_digest bytea not null
    check(octet_length(tracking_secret_digest)=32),
  booking_type_id uuid not null,
  submitted_full_name text not null
    check(submitted_full_name=btrim(submitted_full_name) and char_length(submitted_full_name) between 1 and 200),
  submitted_phone text not null
    check(submitted_phone=btrim(submitted_phone) and char_length(submitted_phone) between 7 and 20),
  submitted_gender text check(submitted_gender is null or submitted_gender in('male','female','child')),
  submitted_date_of_birth date,
  submitted_church text not null default '' check(char_length(submitted_church)<=200),
  submitted_governorate text not null default '' check(char_length(submitted_governorate)<=120),
  submitted_city_or_village text not null default '' check(char_length(submitted_city_or_village)<=160),
  submitted_service_sector text not null default '' check(char_length(submitted_service_sector)<=160),
  submitted_service_sector_other text check(submitted_service_sector_other is null or char_length(submitted_service_sector_other)<=200),
  submitted_notes text check(submitted_notes is null or char_length(submitted_notes)<=4000),
  state text not null default 'submitted'
    check(state in('submitted','under_review','approved','rejected','waitlisted')),
  revision bigint not null default 1 check(revision>0),
  resolved_person_id uuid references platform.people(id) on delete restrict,
  booking_id uuid references reservations.bookings(id) on delete restrict,
  decision_reason text check(decision_reason is null or char_length(decision_reason)<=1000),
  decided_at timestamptz,
  decided_by uuid references platform.profiles(user_id),
  decided_by_device_id uuid references platform.devices(id),
  submitted_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  foreign key(channel_id,event_id)
    references reservations.public_registration_channels(id,event_id) on delete restrict,
  foreign key(event_id,booking_type_id)
    references reservations.booking_types(event_id,id) on delete restrict,
  unique(channel_id,submit_operation_id),
  unique(channel_id,request_reference),
  unique(tracking_secret_digest),
  unique(booking_id),
  check(updated_at>=submitted_at),
  check(
    (state in('submitted','under_review') and decided_at is null and decided_by is null and decided_by_device_id is null and booking_id is null)
    or
    (state in('rejected','waitlisted') and decided_at is not null and decided_by is not null and decided_by_device_id is not null and booking_id is null)
    or
    (state='approved' and decided_at is not null and decided_by is not null and decided_by_device_id is not null and resolved_person_id is not null and booking_id is not null)
  )
);

create index public_registration_requests_event_state_idx
  on reservations.public_registration_requests(event_id,state,submitted_at,id);
create index public_registration_requests_channel_submitted_idx
  on reservations.public_registration_requests(channel_id,submitted_at,id);

alter table reservations.public_registration_channels enable row level security;
alter table reservations.public_registration_channels force row level security;
alter table reservations.public_registration_requests enable row level security;
alter table reservations.public_registration_requests force row level security;

revoke all on reservations.public_registration_channels
  from public,anon,authenticated,service_role;
revoke all on reservations.public_registration_requests
  from public,anon,authenticated,service_role;

commit;
