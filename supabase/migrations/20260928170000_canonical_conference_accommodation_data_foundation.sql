begin;

do $$
begin
  if to_regclass('public.conferences') is null
     or to_regclass('public.conference_participations') is null
     or to_regclass('platform.people') is null
     or to_regclass('platform.profiles') is null then
    raise exception 'P5A_CANONICAL_FOUNDATION_REQUIRED' using errcode='55000';
  end if;
  if not exists(select 1 from public.module_permission_catalog where permission_key='conference.accommodation.view' and module_key='conference' and status='active' and allowed_scope_mode='resource' and allowed_resource_type='conference')
     or not exists(select 1 from public.module_permission_catalog where permission_key='conference.accommodation.manage' and module_key='conference' and status='active' and allowed_scope_mode='resource' and allowed_resource_type='conference') then
    raise exception 'P5A_PERMISSION_CONTRACT_REQUIRED' using errcode='55000';
  end if;
end $$;

create unique index conference_participations_id_conference_idx
  on public.conference_participations(id,conference_id);

create table public.conference_accommodation_houses(
  id uuid primary key default extensions.gen_random_uuid(),
  conference_id uuid not null references public.conferences(id) on delete restrict,
  name text not null check(btrim(name)<>''),
  description text,
  position integer not null default 0 check(position>=0),
  revision bigint not null default 1 check(revision>=1),
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  created_by uuid not null references platform.profiles(user_id) on delete restrict,
  updated_by uuid not null references platform.profiles(user_id) on delete restrict,
  unique(conference_id,id)
);

create table public.conference_accommodation_floors(
  id uuid primary key default extensions.gen_random_uuid(),
  conference_id uuid not null,
  house_id uuid not null,
  name text not null check(btrim(name)<>''),
  position integer not null default 0 check(position>=0),
  revision bigint not null default 1 check(revision>=1),
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  created_by uuid not null references platform.profiles(user_id) on delete restrict,
  updated_by uuid not null references platform.profiles(user_id) on delete restrict,
  constraint conference_accommodation_floors_house_fk
    foreign key(conference_id,house_id)
    references public.conference_accommodation_houses(conference_id,id)
    on delete restrict,
  unique(conference_id,id)
);

create table public.conference_accommodation_rooms(
  id uuid primary key default extensions.gen_random_uuid(),
  conference_id uuid not null,
  floor_id uuid not null,
  room_number text not null check(btrim(room_number)<>''),
  base_capacity integer not null check(base_capacity>=0),
  extra_bed_capacity integer not null default 0 check(extra_bed_capacity>=0),
  notes text,
  is_closed boolean not null default false,
  closed_day integer check(closed_day is null or closed_day>=1),
  position integer not null default 0 check(position>=0),
  revision bigint not null default 1 check(revision>=1),
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  created_by uuid not null references platform.profiles(user_id) on delete restrict,
  updated_by uuid not null references platform.profiles(user_id) on delete restrict,
  constraint conference_accommodation_rooms_floor_fk
    foreign key(conference_id,floor_id)
    references public.conference_accommodation_floors(conference_id,id)
    on delete restrict,
  constraint conference_accommodation_rooms_closed_day_ck
    check(is_closed or closed_day is null),
  unique(conference_id,id)
);

create table public.conference_accommodation_occupancies(
  id uuid primary key default extensions.gen_random_uuid(),
  conference_id uuid not null,
  room_id uuid not null,
  participation_id uuid not null,
  arrival_day integer not null default 1 check(arrival_day>=1),
  leave_day integer,
  bed_type text not null default 'base' check(bed_type in('base','extra')),
  extra_bed_person_type text check(extra_bed_person_type in('adult','child')),
  revision bigint not null default 1 check(revision>=1),
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  created_by uuid not null references platform.profiles(user_id) on delete restrict,
  updated_by uuid not null references platform.profiles(user_id) on delete restrict,
  constraint conference_accommodation_occupancies_room_fk
    foreign key(conference_id,room_id)
    references public.conference_accommodation_rooms(conference_id,id)
    on delete restrict,
  constraint conference_accommodation_occupancies_participation_fk
    foreign key(participation_id,conference_id)
    references public.conference_participations(id,conference_id)
    on delete restrict,
  constraint conference_accommodation_occupancies_stay_ck
    check(leave_day is null or leave_day>arrival_day),
  constraint conference_accommodation_occupancies_bed_ck
    check((bed_type='base' and extra_bed_person_type is null)
       or (bed_type='extra' and extra_bed_person_type is not null)),
  unique(participation_id)
);

create index conference_accommodation_houses_list_idx
  on public.conference_accommodation_houses(conference_id,position,id);
create index conference_accommodation_floors_list_idx
  on public.conference_accommodation_floors(conference_id,house_id,position,id);
create index conference_accommodation_rooms_list_idx
  on public.conference_accommodation_rooms(conference_id,floor_id,position,id);
create index conference_accommodation_occupancies_room_idx
  on public.conference_accommodation_occupancies(conference_id,room_id,arrival_day,id);

alter table public.conference_accommodation_houses enable row level security;
alter table public.conference_accommodation_houses force row level security;
alter table public.conference_accommodation_floors enable row level security;
alter table public.conference_accommodation_floors force row level security;
alter table public.conference_accommodation_rooms enable row level security;
alter table public.conference_accommodation_rooms force row level security;
alter table public.conference_accommodation_occupancies enable row level security;
alter table public.conference_accommodation_occupancies force row level security;

revoke all on table
  public.conference_accommodation_houses,
  public.conference_accommodation_floors,
  public.conference_accommodation_rooms,
  public.conference_accommodation_occupancies
from public,anon,authenticated,service_role;

comment on table public.conference_accommodation_houses is 'Canonical Conference-owned Accommodation house instances; template provenance is intentionally non-authoritative and omitted.';
comment on table public.conference_accommodation_rooms is 'Canonical room capacity and closure data. P5B protected mutations must transactionally enforce active occupancy capacity.';
comment on table public.conference_accommodation_occupancies is 'One current/latest Accommodation assignment per canonical Conference participation. P5B must require active participation and coordinate cleanup before participation deletion.';

commit;
