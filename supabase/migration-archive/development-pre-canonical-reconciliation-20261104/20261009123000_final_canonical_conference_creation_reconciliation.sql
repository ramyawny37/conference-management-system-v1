begin;

-- Final Conference-root prerequisites missing from the clean P3A lineage.
alter table public.conferences
  add column if not exists place text not null default '',
  add constraint conferences_place_check
    check(place=btrim(place) and char_length(place)<=500);

do $$
declare
  v_relation oid:=to_regclass('public.conference_creation_operations');
  v_contract_errors text[]:=array[]::text[];
begin
  if v_relation is null then
    create table public.conference_creation_operations(
      user_id uuid not null references platform.profiles(user_id) on delete restrict,
      operation_id uuid not null,
      conference_id uuid not null unique references public.conferences(id) on delete restrict,
      initial_metadata jsonb not null check(jsonb_typeof(initial_metadata)='object'),
      created_at timestamptz not null default statement_timestamp(),
      primary key(user_id,operation_id)
    );
    return;
  end if;

  if not exists(
    select 1 from pg_class relation
    where relation.oid=v_relation and relation.relkind='r'
  ) then
    v_contract_errors:=array_append(v_contract_errors,'relation_kind');
  end if;

  -- Development can legitimately contain the pre-P6C1 creation ledger. Normalize
  -- that exact historical shape in place; anything else remains fail-closed.
  if exists(
    select 1 from pg_attribute
    where attrelid=v_relation and attnum>0 and not attisdropped and attname in('id','updated_at')
  ) then
    if (
      select array_agg(attname order by attnum)
      from pg_attribute
      where attrelid=v_relation and attnum>0 and not attisdropped
    )<>array['id','user_id','operation_id','conference_id','initial_metadata','created_at','updated_at']::name[]
    or exists(
      select 1 from (values
        ('id','uuid'::text,true),
        ('user_id','uuid',true),
        ('operation_id','uuid',true),
        ('conference_id','uuid',true),
        ('initial_metadata','jsonb',true),
        ('created_at','timestamp with time zone',true),
        ('updated_at','timestamp with time zone',true)
      ) expected(column_name,data_type,is_not_null)
      where not exists(
        select 1 from pg_attribute attribute
        where attribute.attrelid=v_relation and attribute.attnum>0
          and not attribute.attisdropped
          and attribute.attname=expected.column_name
          and format_type(attribute.atttypid,attribute.atttypmod)=expected.data_type
          and attribute.attnotnull=expected.is_not_null
      )
    )
    or not exists(
      select 1 from pg_constraint c
      where c.conrelid=v_relation and c.contype='p'
        and c.conkey=array[(select attnum from pg_attribute where attrelid=v_relation and attname='id')]::smallint[]
    )
    or not exists(
      select 1 from pg_constraint c
      where c.conrelid=v_relation and c.contype='u'
        and c.conkey=array[
          (select attnum from pg_attribute where attrelid=v_relation and attname='user_id'),
          (select attnum from pg_attribute where attrelid=v_relation and attname='operation_id')
        ]::smallint[]
    )
    or not exists(
      select 1 from pg_constraint c
      where c.conrelid=v_relation and c.contype='u'
        and c.conkey=array[(select attnum from pg_attribute where attrelid=v_relation and attname='conference_id')]::smallint[]
    )
    or not exists(
      select 1 from pg_constraint c
      where c.conrelid=v_relation and c.contype='f'
        and c.confrelid='auth.users'::regclass
        and c.conkey=array[(select attnum from pg_attribute where attrelid=v_relation and attname='user_id')]::smallint[]
        and c.confdeltype='c'
    )
    or not exists(
      select 1 from pg_constraint c
      where c.conrelid=v_relation and c.contype='f'
        and c.confrelid='public.conferences'::regclass
        and c.conkey=array[(select attnum from pg_attribute where attrelid=v_relation and attname='conference_id')]::smallint[]
        and c.confdeltype='r'
    )
    or not exists(
      select 1 from pg_constraint c
      where c.conrelid=v_relation and c.contype='c'
        and pg_get_expr(c.conbin,c.conrelid,true)~*'jsonb_typeof[(]initial_metadata[)].*object'
    )
    or exists(
      select 1 from public.conference_creation_operations ledger
      left join platform.profiles profile on profile.user_id=ledger.user_id
      where profile.user_id is null
    ) then
      raise exception 'FINAL_CANONICAL_CONFERENCE_CREATION_LEDGER_INCOMPATIBLE'
        using errcode='55000',detail='historical_shape';
    end if;

    execute format('alter table public.conference_creation_operations drop constraint %I',
      (select conname from pg_constraint where conrelid=v_relation and contype='p'));
    execute format('alter table public.conference_creation_operations drop constraint %I',
      (select conname from pg_constraint where conrelid=v_relation and contype='f'
       and confrelid='auth.users'::regclass
       and conkey=array[(select attnum from pg_attribute where attrelid=v_relation and attname='user_id')]::smallint[]));
    execute format('alter table public.conference_creation_operations drop constraint %I',
      (select conname from pg_constraint where conrelid=v_relation and contype='u'
       and conkey=array[
         (select attnum from pg_attribute where attrelid=v_relation and attname='user_id'),
         (select attnum from pg_attribute where attrelid=v_relation and attname='operation_id')
       ]::smallint[]));

    drop index if exists public.conference_creation_operations_user_created_idx;
    alter table public.conference_creation_operations
      drop column id,
      drop column updated_at,
      alter column initial_metadata drop default,
      alter column created_at set default statement_timestamp(),
      add constraint conference_creation_operations_user_id_fkey
        foreign key(user_id) references platform.profiles(user_id) on delete restrict,
      add constraint conference_creation_operations_pkey primary key(user_id,operation_id);
  end if;

  if exists(
    select 1 from (values
      ('user_id','uuid'::text,true),
      ('operation_id','uuid',true),
      ('conference_id','uuid',true),
      ('initial_metadata','jsonb',true),
      ('created_at','timestamp with time zone',true)
    ) expected(column_name,data_type,is_not_null)
    where not exists(
      select 1 from pg_attribute attribute
      where attribute.attrelid=v_relation and attribute.attnum>0
        and not attribute.attisdropped
        and attribute.attname=expected.column_name
        and format_type(attribute.atttypid,attribute.atttypmod)=expected.data_type
        and attribute.attnotnull=expected.is_not_null
    )
  ) or exists(
    select 1 from pg_attribute attribute
    where attribute.attrelid=v_relation and attribute.attnum>0
      and not attribute.attisdropped
      and attribute.attname not in(
        'user_id','operation_id','conference_id','initial_metadata','created_at'
      )
  ) then
    v_contract_errors:=array_append(v_contract_errors,'columns');
  end if;

  if not exists(
    select 1 from pg_constraint constraint_row
    where constraint_row.conrelid=v_relation and constraint_row.contype='p'
      and constraint_row.conkey=array[
        (select attnum from pg_attribute where attrelid=v_relation and attname='user_id'),
        (select attnum from pg_attribute where attrelid=v_relation and attname='operation_id')
      ]::smallint[]
  ) then
    v_contract_errors:=array_append(v_contract_errors,'primary_key');
  end if;

  if not exists(
    select 1 from pg_constraint constraint_row
    where constraint_row.conrelid=v_relation and constraint_row.contype='u'
      and constraint_row.conkey=array[
        (select attnum from pg_attribute where attrelid=v_relation and attname='conference_id')
      ]::smallint[]
  ) then
    v_contract_errors:=array_append(v_contract_errors,'conference_id_unique');
  end if;

  if not exists(
    select 1 from pg_constraint constraint_row
    where constraint_row.conrelid=v_relation and constraint_row.contype='f'
      and constraint_row.confrelid='platform.profiles'::regclass
      and constraint_row.conkey=array[
        (select attnum from pg_attribute where attrelid=v_relation and attname='user_id')
      ]::smallint[]
      and constraint_row.confkey=array[
        (select attnum from pg_attribute where attrelid='platform.profiles'::regclass and attname='user_id')
      ]::smallint[]
      and constraint_row.confdeltype='r' and constraint_row.confupdtype='a'
      and constraint_row.confmatchtype='s'
  ) or not exists(
    select 1 from pg_constraint constraint_row
    where constraint_row.conrelid=v_relation and constraint_row.contype='f'
      and constraint_row.confrelid='public.conferences'::regclass
      and constraint_row.conkey=array[
        (select attnum from pg_attribute where attrelid=v_relation and attname='conference_id')
      ]::smallint[]
      and constraint_row.confkey=array[
        (select attnum from pg_attribute where attrelid='public.conferences'::regclass and attname='id')
      ]::smallint[]
      and constraint_row.confdeltype='r' and constraint_row.confupdtype='a'
      and constraint_row.confmatchtype='s'
  ) then
    v_contract_errors:=array_append(v_contract_errors,'foreign_keys');
  end if;

  if not exists(
    select 1 from pg_constraint constraint_row
    where constraint_row.conrelid=v_relation and constraint_row.contype='c'
      and regexp_replace(
        pg_get_expr(constraint_row.conbin,constraint_row.conrelid,true),'\s+','','g'
      )='jsonb_typeof(initial_metadata)=''object''::text'
  ) then
    v_contract_errors:=array_append(v_contract_errors,'initial_metadata_object_check');
  end if;

  if not exists(
    select 1 from pg_attrdef default_row
    join pg_attribute attribute
      on attribute.attrelid=default_row.adrelid
     and attribute.attnum=default_row.adnum
    where default_row.adrelid=v_relation and attribute.attname='created_at'
      and pg_get_expr(default_row.adbin,default_row.adrelid)='statement_timestamp()'
  ) then
    v_contract_errors:=array_append(v_contract_errors,'created_at_default');
  end if;

  if exists(
    select 1
    from pg_attribute attribute
    left join pg_attrdef default_row
      on default_row.adrelid=attribute.attrelid
     and default_row.adnum=attribute.attnum
    where attribute.attrelid=v_relation and attribute.attnum>0
      and not attribute.attisdropped
      and (
        attribute.attidentity<>'' or attribute.attgenerated<>''
        or (attribute.attname<>'created_at' and default_row.oid is not null)
      )
  ) then
    v_contract_errors:=array_append(v_contract_errors,'column_generation_or_defaults');
  end if;

  if (
    select count(*) from pg_constraint constraint_row
    where constraint_row.conrelid=v_relation
  )<>5 or exists(
    select 1 from pg_constraint constraint_row
    where constraint_row.conrelid=v_relation
      and (
        not constraint_row.convalidated
        or constraint_row.condeferrable
        or constraint_row.condeferred
        or (constraint_row.contype='c' and constraint_row.connoinherit)
      )
  ) then
    v_contract_errors:=array_append(v_contract_errors,'constraint_set');
  end if;

  if exists(
    select 1 from pg_policy policy
    where policy.polrelid=v_relation
      and not (
        policy.polname='conference_creation_operations_select_own'
        and policy.polcmd='r' and policy.polpermissive
        and policy.polroles=array['authenticated'::regrole]::oid[]
        and pg_get_expr(policy.polqual,policy.polrelid)
            ~* '^\(?user_id = auth\.uid\(\)\)?$'
        and policy.polwithcheck is null
      )
  ) then
    v_contract_errors:=array_append(v_contract_errors,'unexpected_rls_policies');
  end if;

  if exists(
    select 1
    from aclexplode(coalesce(
      (select relation.relacl from pg_class relation where relation.oid=v_relation),
      acldefault('r',(select relation.relowner from pg_class relation where relation.oid=v_relation))
    )) privilege
    where privilege.grantee<>0
      and privilege.grantee not in(
        'anon'::regrole,'authenticated'::regrole,'service_role'::regrole,
        (select relation.relowner from pg_class relation where relation.oid=v_relation)
      )
  ) then
    v_contract_errors:=array_append(v_contract_errors,'unexpected_acl_grantee');
  end if;

  if exists(
    select 1 from pg_attribute attribute
    where attribute.attrelid=v_relation and attribute.attnum>0
      and not attribute.attisdropped and attribute.attacl is not null
  ) then
    v_contract_errors:=array_append(v_contract_errors,'column_acl');
  end if;

  if cardinality(v_contract_errors)>0 then
    raise exception 'FINAL_CANONICAL_CONFERENCE_CREATION_LEDGER_INCOMPATIBLE'
      using errcode='55000',detail=array_to_string(v_contract_errors,',');
  end if;
end $$;
drop policy if exists conference_creation_operations_select_own
  on public.conference_creation_operations;
alter table public.conference_creation_operations enable row level security;
alter table public.conference_creation_operations force row level security;
revoke all on table public.conference_creation_operations
  from public,anon,authenticated,service_role;

-- Final cutover: remove the remaining pre-Platform Conference authority.
drop function if exists public.device_guarded_create_conference_idempotent(uuid,uuid,uuid,text,jsonb);
drop function if exists public.create_conference_idempotent(uuid,uuid,text,jsonb);
drop function if exists public.can_user_create_conferences(uuid);
drop function if exists public.set_user_conference_creation_permission(uuid,boolean);
drop function if exists public.is_conference_owner(uuid);
drop function if exists public.enforce_launch_conference_member_contract();
drop function if exists public.protect_conference_owner_membership();

-- Restore only the final server-native Conference creation capability after
-- Conference membership retirement. Platform permissions remain the sole authority.
do $$
begin
  if to_regclass('public.conferences') is null
     or to_regclass('public.organizations') is null
     or to_regclass('public.module_permission_catalog') is null
     or to_regclass('public.module_permission_grants') is null
     or to_regclass('platform.audit_events') is null
     or to_regprocedure('public.require_effective_module_permission(uuid,text,text,text,text)') is null
     or to_regprocedure('platform_private.validated_phase1c_device_authorization(uuid,uuid)') is null
     or to_regprocedure('platform_private.require_exact_jsonb_keys(jsonb,text[],text[])') is null
     or to_regprocedure('platform.execute_conference_device_operation(uuid,uuid,bytea,text,jsonb)') is null
     or to_regprocedure('platform.execute_conference_device_operation_phase1c_core(uuid,uuid,bytea,text,jsonb)') is null
     or to_regclass('platform.people') is null
     or to_regclass('platform.profiles') is null then
    raise exception 'FINAL_CANONICAL_CONFERENCE_CREATION_FOUNDATION_REQUIRED' using errcode='55000';
  end if;

  if to_regclass('public.conference_members') is not null
     or to_regprocedure('public.is_conference_member(uuid)') is not null
     or exists(
       select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname in(
         'has_conference_role','create_organization_conference_idempotent',
         'device_guarded_create_organization_conference_idempotent'
       )
     ) then
    raise exception 'RETIRED_CONFERENCE_AUTHORITY_MUST_REMAIN_ABSENT' using errcode='55000';
  end if;

  if exists(
    select 1 from (values
      ('conference.lifecycle.create','module',null::text),
      ('conference.access.view','resource','conference'),
      ('conference.lifecycle.manage','resource','conference')
    ) expected(permission_key,scope_mode,resource_type)
    where not exists(
      select 1 from public.module_permission_catalog catalog
      where catalog.permission_key=expected.permission_key
        and catalog.module_key='conference' and catalog.status='active'
        and catalog.allowed_scope_mode=expected.scope_mode
        and catalog.allowed_resource_type is not distinct from expected.resource_type
    )
  ) then
    raise exception 'FINAL_CANONICAL_CONFERENCE_PERMISSION_CONTRACT_REQUIRED' using errcode='55000';
  end if;
end $$;

-- The clean lineage ends at P3A. Everything below is created in final form;
-- none of the skipped transitional migrations is a prerequisite.
create table public.conference_participations(
  id uuid primary key default extensions.gen_random_uuid(),
  conference_id uuid not null references public.conferences(id) on delete restrict,
  person_id uuid not null references platform.people(id) on delete restrict,
  guardian_participation_id uuid null,
  status text not null default 'active' check(status in('active','apologized')),
  revision bigint not null default 1 check(revision>=1),
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  created_by uuid not null references platform.profiles(user_id) on delete restrict,
  updated_by uuid not null references platform.profiles(user_id) on delete restrict,
  unique(conference_id,person_id),unique(id,conference_id),
  foreign key(guardian_participation_id,conference_id)
    references public.conference_participations(id,conference_id) on delete restrict,
  check(guardian_participation_id is null or guardian_participation_id<>id)
);
create index conference_participations_list_idx
  on public.conference_participations(conference_id,status,created_at,id);
create index conference_participations_guardian_idx
  on public.conference_participations(conference_id,guardian_participation_id)
  where guardian_participation_id is not null;

create table public.conference_participation_operations(
  actor_user_id uuid not null references platform.profiles(user_id) on delete restrict,
  operation_id uuid not null,
  operation text not null,
  request jsonb not null check(jsonb_typeof(request)='object'),
  result jsonb not null check(jsonb_typeof(result)='object'),
  created_at timestamptz not null default statement_timestamp(),
  primary key(actor_user_id,operation_id)
);
alter table public.conference_participations enable row level security;
alter table public.conference_participations force row level security;
alter table public.conference_participation_operations enable row level security;
alter table public.conference_participation_operations force row level security;
revoke all on table public.conference_participations,
  public.conference_participation_operations
from public,anon,authenticated,service_role;

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
comment on table public.conference_accommodation_rooms is 'Canonical room capacity and closure data. closed_day is the first unavailable Conference day; null while closed means immediately/fully closed. P5B must validate duration and transactionally enforce closure and capacity.';
comment on table public.conference_accommodation_occupancies is 'One current/latest Accommodation assignment per canonical Conference participation. P5B must validate Conference duration, require active participation, remove Accommodation effect on apology, and preserve moves in immutable audit evidence.';

-- Final schema extracted from 20261003140000_canonical_conference_transport_foundation.sql.
create table public.conference_transport_vehicles(
  id uuid primary key default extensions.gen_random_uuid(), conference_id uuid not null references public.conferences(id) on delete cascade,
  name text not null check(length(btrim(name)) between 1 and 160), icon text not null default '🚌' check(length(icon)<=32),
  capacity integer not null check(capacity between 1 and 300), position integer not null default 0 check(position>=0),
  revision bigint not null default 1 check(revision>=1), created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(), created_by uuid not null references platform.profiles(user_id),
  updated_by uuid not null references platform.profiles(user_id), unique(conference_id,id), unique(conference_id,name)
);
create index conference_transport_vehicles_list_idx on public.conference_transport_vehicles(conference_id,position,id);

create table public.conference_transport_assignments(
  id uuid primary key default extensions.gen_random_uuid(), conference_id uuid not null references public.conferences(id) on delete cascade,
  vehicle_id uuid not null, participation_id uuid not null,
  assignment_mode text not null check(assignment_mode in('independent','shared')),
  rider_kind text not null check(rider_kind in('adult','child','infant')),
  seat_number integer check(seat_number between 1 and 300), revision bigint not null default 1 check(revision>=1),
  created_at timestamptz not null default statement_timestamp(), updated_at timestamptz not null default statement_timestamp(),
  created_by uuid not null references platform.profiles(user_id), updated_by uuid not null references platform.profiles(user_id),
  foreign key(conference_id,vehicle_id) references public.conference_transport_vehicles(conference_id,id) on delete cascade,
  foreign key(participation_id,conference_id) references public.conference_participations(id,conference_id) on delete cascade,
  unique(conference_id,participation_id),
  check((assignment_mode='independent' and seat_number is not null) or (assignment_mode='shared' and seat_number is null))
);
create unique index conference_transport_unique_seat_idx on public.conference_transport_assignments(vehicle_id,seat_number) where seat_number is not null;
create index conference_transport_assignments_list_idx on public.conference_transport_assignments(conference_id,vehicle_id,seat_number,id);

alter table public.conference_transport_vehicles enable row level security; alter table public.conference_transport_vehicles force row level security;
alter table public.conference_transport_assignments enable row level security; alter table public.conference_transport_assignments force row level security;
revoke all on table public.conference_transport_vehicles,public.conference_transport_assignments from public,anon,authenticated,service_role;

-- Final schema extracted from 20261003160000_canonical_conference_restaurant_foundation.sql.
create table public.conference_restaurant_settings(
  conference_id uuid primary key references public.conferences(id) on delete cascade,
  enabled boolean not null default true, first_meal text not null default 'dinner' check(first_meal in('breakfast','lunch','dinner')),
  last_meal text not null default 'lunch' check(last_meal in('breakfast','lunch','dinner')),
  breakfast_price numeric(12,2) not null default 0 check(breakfast_price>=0), lunch_price numeric(12,2) not null default 0 check(lunch_price>=0), dinner_price numeric(12,2) not null default 0 check(dinner_price>=0),
  revision bigint not null default 1 check(revision>=1),created_at timestamptz not null default statement_timestamp(),updated_at timestamptz not null default statement_timestamp(),created_by uuid not null references platform.profiles(user_id),updated_by uuid not null references platform.profiles(user_id)
);
create table public.conference_restaurant_price_overrides(
  id uuid primary key default extensions.gen_random_uuid(),conference_id uuid not null references public.conferences(id) on delete cascade,
  day_number integer not null check(day_number>=1),meal text not null check(meal in('breakfast','lunch','dinner')),price numeric(12,2) not null check(price>=0),revision bigint not null default 1 check(revision>=1),
  created_at timestamptz not null default statement_timestamp(),updated_at timestamptz not null default statement_timestamp(),created_by uuid not null references platform.profiles(user_id),updated_by uuid not null references platform.profiles(user_id),unique(conference_id,day_number,meal)
);
create table public.conference_restaurant_count_overrides(
  id uuid primary key default extensions.gen_random_uuid(),conference_id uuid not null references public.conferences(id) on delete cascade,
  day_number integer not null check(day_number>=1),meal text not null check(meal in('breakfast','lunch','dinner')),extra_count integer not null default 0 check(extra_count>=0),deduction_count integer not null default 0 check(deduction_count>=0),note text check(note is null or length(note)<=120),revision bigint not null default 1 check(revision>=1),
  created_at timestamptz not null default statement_timestamp(),updated_at timestamptz not null default statement_timestamp(),created_by uuid not null references platform.profiles(user_id),updated_by uuid not null references platform.profiles(user_id),unique(conference_id,day_number,meal),check(extra_count>0 or deduction_count>0)
);
create table public.conference_restaurant_participation_overrides(
  id uuid primary key default extensions.gen_random_uuid(),conference_id uuid not null references public.conferences(id) on delete cascade,participation_id uuid not null,
  day_number integer not null check(day_number>=1),meal text not null check(meal in('breakfast','lunch','dinner')),included boolean not null,note text check(note is null or length(note)<=120),revision bigint not null default 1 check(revision>=1),
  created_at timestamptz not null default statement_timestamp(),updated_at timestamptz not null default statement_timestamp(),created_by uuid not null references platform.profiles(user_id),updated_by uuid not null references platform.profiles(user_id),
  foreign key(participation_id,conference_id) references public.conference_participations(id,conference_id) on delete restrict,unique(conference_id,participation_id,day_number,meal)
);
create index conference_restaurant_participation_overrides_participation_idx on public.conference_restaurant_participation_overrides(participation_id,id);

alter table public.conference_restaurant_settings enable row level security;alter table public.conference_restaurant_settings force row level security;
alter table public.conference_restaurant_price_overrides enable row level security;alter table public.conference_restaurant_price_overrides force row level security;
alter table public.conference_restaurant_count_overrides enable row level security;alter table public.conference_restaurant_count_overrides force row level security;
alter table public.conference_restaurant_participation_overrides enable row level security;alter table public.conference_restaurant_participation_overrides force row level security;
revoke all on table public.conference_restaurant_settings,public.conference_restaurant_price_overrides,public.conference_restaurant_count_overrides,public.conference_restaurant_participation_overrides from public,anon,authenticated,service_role;

-- Final schema extracted from 20261003180000_canonical_conference_accommodation_pricing.sql.
create table public.conference_accommodation_pricing(
  conference_id uuid primary key references public.conferences(id) on delete cascade,
  enabled boolean not null default true,
  pricing_mode text not null default 'per_person_night' check(pricing_mode in('per_person_night','per_room_night','per_person_day','per_room_day','fixed_package','per_day_package','room_type')),
  person_night numeric(14,2) not null default 0 check(person_night>=0),
  room_night numeric(14,2) not null default 0 check(room_night>=0),
  person_day numeric(14,2) not null default 0 check(person_day>=0),
  room_day numeric(14,2) not null default 0 check(room_day>=0),
  package_price numeric(14,2) not null default 0 check(package_price>=0),
  package_day_price numeric(14,2) not null default 0 check(package_day_price>=0),
  single_price numeric(14,2) not null default 0 check(single_price>=0),
  double_price numeric(14,2) not null default 0 check(double_price>=0),
  triple_price numeric(14,2) not null default 0 check(triple_price>=0),
  quadruple_price numeric(14,2) not null default 0 check(quadruple_price>=0),
  quintuple_price numeric(14,2) not null default 0 check(quintuple_price>=0),
  sextuple_price numeric(14,2) not null default 0 check(sextuple_price>=0),
  seven_plus_price numeric(14,2) not null default 0 check(seven_plus_price>=0),
  revision bigint not null default 1 check(revision>=1),
  created_at timestamptz not null default statement_timestamp(),
  created_by uuid not null references platform.profiles(user_id),
  updated_at timestamptz not null default statement_timestamp(),
  updated_by uuid not null references platform.profiles(user_id)
);
alter table public.conference_accommodation_pricing enable row level security;
alter table public.conference_accommodation_pricing force row level security;
revoke all on table public.conference_accommodation_pricing from public,anon,authenticated,service_role;

-- Final schema extracted from 20261003200000_canonical_conference_air_conditioning.sql.
create table public.conference_air_conditioning_defaults(
 conference_id uuid primary key references public.conferences(id) on delete cascade,enabled boolean not null default true,
 pricing_basis text not null default 'PER_ROOM' check(pricing_basis in('PER_PERSON','PER_ROOM','PER_UNIT','FIXED','INCLUDED')),
 time_basis text not null default 'DAY' check(time_basis in('DAY','NIGHT','CONFERENCE')),
 duration_basis text not null default 'CONFERENCE' check(duration_basis in('CONFERENCE','ACTUAL_OCCUPANCY')),
 unit_price numeric(14,2) not null default 0 check(unit_price>=0),fixed_amount numeric(14,2) check(fixed_amount is null or fixed_amount>=0),
 include_empty_rooms boolean not null default false,include_closed_rooms boolean not null default false,units_count integer check(units_count is null or units_count>=0),
 revision bigint not null default 1 check(revision>=1),created_at timestamptz not null default statement_timestamp(),updated_at timestamptz not null default statement_timestamp(),created_by uuid not null references platform.profiles(user_id),updated_by uuid not null references platform.profiles(user_id),check((pricing_basis='FIXED')=(fixed_amount is not null))
);
create table public.conference_air_conditioning_house_overrides(
 house_id uuid primary key references public.conference_accommodation_houses(id) on delete cascade,conference_id uuid not null references public.conferences(id) on delete cascade,
 enabled boolean,pricing_basis text check(pricing_basis is null or pricing_basis in('PER_PERSON','PER_ROOM','PER_UNIT','FIXED','INCLUDED')),time_basis text check(time_basis is null or time_basis in('DAY','NIGHT','CONFERENCE')),duration_basis text check(duration_basis is null or duration_basis in('CONFERENCE','ACTUAL_OCCUPANCY')),unit_price numeric(14,2) check(unit_price is null or unit_price>=0),fixed_amount numeric(14,2) check(fixed_amount is null or fixed_amount>=0),include_empty_rooms boolean,include_closed_rooms boolean,units_count integer check(units_count is null or units_count>=0),revision bigint not null default 1 check(revision>=1),created_at timestamptz not null default statement_timestamp(),updated_at timestamptz not null default statement_timestamp(),created_by uuid not null references platform.profiles(user_id),updated_by uuid not null references platform.profiles(user_id),unique(house_id,conference_id),check(fixed_amount is null or pricing_basis='FIXED')
);
create table public.conference_air_conditioning_room_overrides(
 room_id uuid primary key references public.conference_accommodation_rooms(id) on delete cascade,conference_id uuid not null references public.conferences(id) on delete cascade,
 included boolean,enabled boolean,pricing_basis text check(pricing_basis is null or pricing_basis in('PER_PERSON','PER_ROOM','PER_UNIT','FIXED','INCLUDED')),time_basis text check(time_basis is null or time_basis in('DAY','NIGHT','CONFERENCE')),duration_basis text check(duration_basis is null or duration_basis in('CONFERENCE','ACTUAL_OCCUPANCY')),unit_price numeric(14,2) check(unit_price is null or unit_price>=0),fixed_amount numeric(14,2) check(fixed_amount is null or fixed_amount>=0),include_empty_rooms boolean,include_closed_rooms boolean,units_count integer check(units_count is null or units_count>=0),revision bigint not null default 1 check(revision>=1),created_at timestamptz not null default statement_timestamp(),updated_at timestamptz not null default statement_timestamp(),created_by uuid not null references platform.profiles(user_id),updated_by uuid not null references platform.profiles(user_id),unique(room_id,conference_id),check(fixed_amount is null or pricing_basis='FIXED')
);
alter table public.conference_air_conditioning_defaults enable row level security;alter table public.conference_air_conditioning_defaults force row level security;
alter table public.conference_air_conditioning_house_overrides enable row level security;alter table public.conference_air_conditioning_house_overrides force row level security;
alter table public.conference_air_conditioning_room_overrides enable row level security;alter table public.conference_air_conditioning_room_overrides force row level security;
revoke all on table public.conference_air_conditioning_defaults,public.conference_air_conditioning_house_overrides,public.conference_air_conditioning_room_overrides from public,anon,authenticated,service_role;

-- Final schema extracted from 20261004140000_canonical_conference_finance_foundation.sql.
create table public.conference_finance_settings(
 conference_id uuid primary key references public.conferences(id) on delete cascade,
 currency text not null default 'EGP' check(length(btrim(currency)) between 1 and 12),rounding_precision smallint not null default 2 check(rounding_precision between 0 and 6),
 expenses_enabled boolean not null default true,income_enabled boolean not null default true,settlements_enabled boolean not null default true,adjustments_enabled boolean not null default true,
 revision bigint not null default 1 check(revision>=1),created_at timestamptz not null default statement_timestamp(),updated_at timestamptz not null default statement_timestamp(),created_by uuid not null references platform.profiles(user_id),updated_by uuid not null references platform.profiles(user_id)
);
create table public.conference_finance_items(
 id uuid primary key,conference_id uuid not null references public.conferences(id) on delete cascade,kind text not null check(kind in('EXPENSE','INCOME','SETTLEMENT')),
 name text not null default '',enabled boolean not null default true,calculation_method text not null check(calculation_method in('fixed','quantity_price','per_day','per_room','per_person','manual')),
 target text check(target is null or target in('expense','income')),operation text check(operation is null or operation in('add','subtract')),
 quantity numeric(14,2) check(quantity is null or quantity>=0),unit_price numeric(14,2) check(unit_price is null or unit_price>=0),amount numeric(14,2) check(amount is null or amount>=0),notes text not null default '',
 revision bigint not null default 1 check(revision>=1),created_at timestamptz not null default statement_timestamp(),updated_at timestamptz not null default statement_timestamp(),created_by uuid not null references platform.profiles(user_id),updated_by uuid not null references platform.profiles(user_id),
 unique(conference_id,id),check((kind='SETTLEMENT')=(target is not null and operation is not null))
);
create table public.conference_finance_adjustments(
 id uuid primary key,conference_id uuid not null references public.conferences(id) on delete cascade,type text not null check(type in('addition','deduction')),category text not null check(category in('accommodation','restaurant','air_conditioning','other')),amount numeric(14,2) not null check(amount>0),note text not null default '',revision bigint not null default 1 check(revision>=1),created_at timestamptz not null default statement_timestamp(),updated_at timestamptz not null default statement_timestamp(),created_by uuid not null references platform.profiles(user_id),updated_by uuid not null references platform.profiles(user_id),unique(conference_id,id)
);
alter table public.conference_finance_settings enable row level security;alter table public.conference_finance_settings force row level security;
alter table public.conference_finance_items enable row level security;alter table public.conference_finance_items force row level security;
alter table public.conference_finance_adjustments enable row level security;alter table public.conference_finance_adjustments force row level security;
revoke all on table public.conference_finance_settings,public.conference_finance_items,public.conference_finance_adjustments from public,anon,authenticated,service_role;
-- Final schema extracted from 20261006120000_canonical_conference_branding_foundation.sql.
create function platform_private.is_prepared_jpeg_data_url(p_value text)
returns boolean language sql immutable set search_path='' as $$
  select p_value~'^data:image/jpeg;base64,[A-Za-z0-9+/]+={0,2}$'
    and length(p_value)<=2097180
$$;
create table public.conference_branding(
  conference_id uuid primary key references public.conferences(id) on delete cascade,
  banner text not null default '',
  service_logo text not null default '',
  auto_colors boolean not null default false,
  banner_position text not null default 'center' check(banner_position in('top','center','bottom')),
  card_theme text not null default 'classic' check(card_theme in('classic','modern-banner')),
  primary_color text not null default '#6C3483' check(primary_color~'^#[0-9A-Fa-f]{6}$'),
  secondary_color text not null default '#8E44AD' check(secondary_color~'^#[0-9A-Fa-f]{6}$'),
  text_color text not null default '#1A2A3A' check(text_color~'^#[0-9A-Fa-f]{6}$'),
  revision bigint not null default 1 check(revision>=1),
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  updated_by uuid references platform.profiles(user_id),
  check(banner='' or platform_private.is_prepared_jpeg_data_url(banner)),
  check(service_logo='' or platform_private.is_prepared_jpeg_data_url(service_logo))
);
alter table public.conference_branding enable row level security;
alter table public.conference_branding force row level security;
revoke all on table public.conference_branding from public,anon,authenticated,service_role;

insert into public.conference_branding(conference_id) select id from public.conferences on conflict do nothing;

-- Final schema extracted from 20261007120000_canonical_accommodation_pricing_room_inclusion.sql.
create table public.conference_accommodation_pricing_room_exclusions(
  conference_id uuid not null,
  room_id uuid not null,
  created_at timestamptz not null default statement_timestamp(),
  created_by uuid not null references platform.profiles(user_id) on delete restrict,
  primary key(conference_id,room_id),
  constraint conference_accommodation_pricing_room_exclusions_room_fk
    foreign key(conference_id,room_id)
    references public.conference_accommodation_rooms(conference_id,id)
    on delete cascade
);
alter table public.conference_accommodation_pricing_room_exclusions enable row level security;
alter table public.conference_accommodation_pricing_room_exclusions force row level security;
revoke all on table public.conference_accommodation_pricing_room_exclusions from public,anon,authenticated,service_role;











































-- Final platform_private.require_conference_participation_context.
create or replace function platform_private.require_conference_participation_context(p_device_id uuid,p_conference_id uuid,p_permission text,p_mutation boolean)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_context jsonb; v_conference public.conferences%rowtype; v_actor uuid;
begin
  if p_conference_id is null or p_permission not in('conference.people.view','conference.people.manage') then raise exception 'CONFERENCE_PARTICIPATION_ARGUMENT_INVALID' using errcode='22023'; end if;
  v_context:=public.require_effective_module_permission(p_device_id,'conference',p_permission,'conference',p_conference_id::text);
  v_actor:=(v_context->>'actorUserId')::uuid;
  if platform_private.validated_phase1c_device_authorization(v_actor,p_device_id) is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  select * into v_conference from public.conferences where id=p_conference_id;
  if not found or v_conference.deleted_at is not null then raise exception 'CONFERENCE_NOT_FOUND' using errcode='P0002'; end if;
  if p_mutation and v_conference.status<>'active' then raise exception 'COMPLETED_CONFERENCE_IMMUTABLE' using errcode='55000'; end if;
  return v_context;
end $$;

-- Final public.create_conference_participation.
create or replace function public.create_conference_participation(p_actor_device_id uuid,p_operation_id uuid,p_conference_id uuid,p_person_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_context jsonb; v_actor uuid; v_device_authorization uuid; v_request jsonb; v_prior public.conference_participation_operations%rowtype; v_row public.conference_participations%rowtype; v_result jsonb;
begin
  if p_operation_id is null or p_person_id is null then raise exception 'CONFERENCE_PARTICIPATION_ARGUMENT_INVALID' using errcode='22023'; end if;
  v_context:=platform_private.require_conference_participation_context(p_actor_device_id,p_conference_id,'conference.people.manage',true); v_actor:=(v_context->>'actorUserId')::uuid;
  v_device_authorization:=platform_private.validated_phase1c_device_authorization(v_actor,p_actor_device_id);
  v_request:=jsonb_build_object('conferenceId',p_conference_id,'personId',p_person_id);
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into v_prior from public.conference_participation_operations where actor_user_id=v_actor and operation_id=p_operation_id;
  if found then if v_prior.operation<>'create' or v_prior.request<>v_request then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023'; end if; return v_prior.result; end if;
  if not exists(select 1 from platform.people where id=p_person_id) then raise exception 'PLATFORM_PERSON_NOT_FOUND' using errcode='23503'; end if;
  if exists(select 1 from public.conference_participations where conference_id=p_conference_id and person_id=p_person_id) then raise exception 'CONFERENCE_PARTICIPATION_ALREADY_EXISTS' using errcode='23505'; end if;
  insert into public.conference_participations(conference_id,person_id,created_by,updated_by) values(p_conference_id,p_person_id,v_actor,v_actor) returning * into v_row;
  v_result:=jsonb_build_object('participationId',v_row.id,'conferenceId',v_row.conference_id,'personId',v_row.person_id,'status',v_row.status,'revision',v_row.revision,'createdAt',v_row.created_at,'updatedAt',v_row.updated_at,'createdBy',v_row.created_by,'updatedBy',v_row.updated_by);
  insert into public.conference_participation_operations values(v_actor,p_operation_id,'create',v_request,v_result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source) values(v_actor,v_device_authorization,'platform','conference','conference.participation.created','conference_participation',v_row.id,'platform',null,jsonb_build_object('conferenceId',p_conference_id,'personId',p_person_id,'status','active','revision',1),jsonb_build_object('permissionKey','conference.people.manage','authoritySource',v_context->>'authoritySource','grantId',v_context->'grantId'),p_operation_id,'rpc');
  return v_result;
end $$;

-- Final public.create_conference_participation_with_person.
create or replace function public.create_conference_participation_with_person(
  p_actor_device_id uuid,p_operation_id uuid,p_conference_id uuid,p_full_name text,
  p_phone text,p_gender text,p_date_of_birth date,p_church text
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_context jsonb; v_actor uuid; v_device_authorization uuid; v_request jsonb;
  v_prior public.conference_participation_operations%rowtype; v_person platform.people%rowtype;
  v_participation public.conference_participations%rowtype; v_person_projection jsonb; v_result jsonb;
begin
  if p_operation_id is null or p_conference_id is null or p_full_name is null or btrim(p_full_name)=''
     or length(btrim(p_full_name))>240
     or (p_phone is not null and (btrim(p_phone)='' or length(btrim(p_phone))>40))
     or (p_gender is not null and p_gender not in('male','female'))
     or (p_church is not null and (btrim(p_church)='' or length(btrim(p_church))>200)) then
    raise exception 'CONFERENCE_PARTICIPANT_PERSON_ARGUMENT_INVALID' using errcode='22023';
  end if;
  v_context:=platform_private.require_conference_participation_context(p_actor_device_id,p_conference_id,'conference.people.manage',true);
  v_actor:=(v_context->>'actorUserId')::uuid;
  v_device_authorization:=platform_private.validated_phase1c_device_authorization(v_actor,p_actor_device_id);
  if v_device_authorization is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  v_request:=jsonb_build_object('conferenceId',p_conference_id,'fullName',btrim(p_full_name),
    'phone',case when p_phone is null then null else btrim(p_phone) end,'gender',p_gender,
    'dateOfBirth',p_date_of_birth,'church',case when p_church is null then null else btrim(p_church) end);
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into v_prior from public.conference_participation_operations where actor_user_id=v_actor and operation_id=p_operation_id;
  if found then
    if v_prior.operation<>'create_with_person' or v_prior.request<>v_request then
      raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';
    end if;
    return v_prior.result;
  end if;
  insert into platform.people(full_name,phone,gender,date_of_birth,church,created_by,updated_by)
  values(btrim(p_full_name),case when p_phone is null then null else btrim(p_phone) end,p_gender,p_date_of_birth,
    case when p_church is null then null else btrim(p_church) end,v_actor,v_actor) returning * into v_person;
  insert into public.conference_participations(conference_id,person_id,created_by,updated_by)
  values(p_conference_id,v_person.id,v_actor,v_actor) returning * into v_participation;
  v_person_projection:=jsonb_build_object('personId',v_person.id,'fullName',v_person.full_name,'phone',v_person.phone,
    'gender',v_person.gender,'dateOfBirth',v_person.date_of_birth,'church',v_person.church);
  v_result:=jsonb_build_object('participationId',v_participation.id,'conferenceId',v_participation.conference_id,
    'personId',v_participation.person_id,'status',v_participation.status,'revision',v_participation.revision,
    'createdAt',v_participation.created_at,'updatedAt',v_participation.updated_at,'createdBy',v_participation.created_by,
    'updatedBy',v_participation.updated_by,'person',v_person_projection);
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at)
  values(v_actor,p_operation_id,'create_with_person',v_request,v_result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,
    entity_id,scope_type,new_values,metadata,operation_id,source)
  values(v_actor,v_device_authorization,'platform','conference','platform.person.created','person',v_person.id,
      'platform',v_person_projection,jsonb_build_object('conferenceId',p_conference_id,'participationId',v_participation.id,
        'permissionKey','conference.people.manage','authoritySource',v_context->>'authoritySource','grantId',v_context->'grantId'),p_operation_id,'rpc'),
    (v_actor,v_device_authorization,'platform','conference','conference.participation.created','conference_participation',
      v_participation.id,'platform',v_result,jsonb_build_object('conferenceId',p_conference_id,'personId',v_person.id,
        'permissionKey','conference.people.manage','authoritySource',v_context->>'authoritySource','grantId',v_context->'grantId'),p_operation_id,'rpc');
  return v_result;
end $$;

-- Final public.list_conference_participations.
create or replace function public.list_conference_participations(p_actor_device_id uuid,p_conference_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_context jsonb; v_items jsonb; v_total bigint; v_active bigint; v_apologized bigint;
begin
  v_context:=platform_private.require_conference_participation_context(p_actor_device_id,p_conference_id,'conference.people.view',false);
  select count(*),count(*) filter(where participation.status='active'),count(*) filter(where participation.status='apologized'),
    coalesce(jsonb_agg(jsonb_build_object('participationId',participation.id,'conferenceId',participation.conference_id,
      'personId',participation.person_id,'status',participation.status,'revision',participation.revision,
      'guardianParticipationId',guardian.id,'guardianPersonId',guardian_person.id,
      'guardianFullName',guardian_person.full_name,'guardianParticipationStatus',guardian.status,
      'createdAt',participation.created_at,'updatedAt',participation.updated_at,'createdBy',participation.created_by,
      'updatedBy',participation.updated_by,'person',jsonb_build_object('personId',person.id,
        'fullName',person.full_name,'phone',person.phone,'gender',person.gender,
        'dateOfBirth',person.date_of_birth,'church',person.church))
      order by participation.created_at,participation.id),'[]'::jsonb)
  into v_total,v_active,v_apologized,v_items
  from public.conference_participations participation
  join platform.people person on person.id=participation.person_id
  left join public.conference_participations guardian on guardian.id=participation.guardian_participation_id
  left join platform.people guardian_person on guardian_person.id=guardian.person_id
  where participation.conference_id=p_conference_id;
  return jsonb_build_object('conferenceId',p_conference_id,'totalCount',v_total,'activeCount',v_active,
    'apologizedCount',v_apologized,'items',v_items);
end $$;

-- Final public.set_conference_participation_guardian.
create or replace function public.set_conference_participation_guardian(
  p_actor_device_id uuid,p_operation_id uuid,p_participation_id uuid,
  p_expected_revision bigint,p_guardian_participation_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_child public.conference_participations%rowtype; v_updated public.conference_participations%rowtype;
  v_guardian public.conference_participations%rowtype; v_context jsonb; v_actor uuid; v_device_authorization uuid;
  v_request jsonb; v_prior public.conference_participation_operations%rowtype; v_result jsonb;
  v_guardian_person platform.people%rowtype;
begin
  if p_operation_id is null or p_participation_id is null or p_expected_revision is null or p_expected_revision<1 then
    raise exception 'CONFERENCE_GUARDIAN_ARGUMENT_INVALID' using errcode='22023';
  end if;
  select * into v_child from public.conference_participations where id=p_participation_id;
  if not found then raise exception 'CONFERENCE_PARTICIPATION_NOT_FOUND' using errcode='P0002'; end if;
  v_context:=platform_private.require_conference_participation_context(
    p_actor_device_id,v_child.conference_id,'conference.people.manage',true);
  v_actor:=(v_context->>'actorUserId')::uuid;
  v_device_authorization:=platform_private.validated_phase1c_device_authorization(v_actor,p_actor_device_id);
  if v_device_authorization is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  v_request:=jsonb_build_object('participationId',p_participation_id,'expectedRevision',p_expected_revision,
    'guardianParticipationId',p_guardian_participation_id);
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into v_prior from public.conference_participation_operations
  where actor_user_id=v_actor and operation_id=p_operation_id;
  if found then
    if v_prior.operation<>'set_guardian' or v_prior.request<>v_request then
      raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';
    end if;
    return v_prior.result;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('conference-guardian:'||v_child.conference_id::text,0));
  perform 1 from public.conference_participations
  where id in(p_participation_id,p_guardian_participation_id) order by id for update;
  select * into v_child from public.conference_participations where id=p_participation_id;
  if not found then raise exception 'CONFERENCE_PARTICIPATION_NOT_FOUND' using errcode='P0002'; end if;
  v_context:=platform_private.require_conference_participation_context(
    p_actor_device_id,v_child.conference_id,'conference.people.manage',true);
  if (v_context->>'actorUserId')::uuid is distinct from v_actor then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end if;
  if v_child.revision<>p_expected_revision then
    raise exception 'CONFERENCE_PARTICIPATION_REVISION_CONFLICT' using errcode='40001';
  end if;
  if p_guardian_participation_id is not null then
    if p_guardian_participation_id=p_participation_id then
      raise exception 'CONFERENCE_GUARDIAN_SELF_REFERENCE' using errcode='23514';
    end if;
    select * into v_guardian from public.conference_participations where id=p_guardian_participation_id;
    if not found or v_guardian.conference_id<>v_child.conference_id then
      raise exception 'CONFERENCE_GUARDIAN_SAME_CONFERENCE_REQUIRED' using errcode='23503';
    end if;
    if v_guardian.guardian_participation_id is not null
       or exists(select 1 from public.conference_participations
         where conference_id=v_child.conference_id and guardian_participation_id=v_child.id) then
      raise exception 'CONFERENCE_GUARDIAN_ONE_LEVEL_REQUIRED' using errcode='23514';
    end if;
  end if;
  update public.conference_participations
  set guardian_participation_id=p_guardian_participation_id,revision=revision+1,
      updated_at=statement_timestamp(),updated_by=v_actor
  where id=p_participation_id returning * into v_updated;
  if v_updated.guardian_participation_id is not null then
    select * into v_guardian from public.conference_participations
    where id=v_updated.guardian_participation_id;
    select * into v_guardian_person from platform.people where id=v_guardian.person_id;
  end if;
  v_result:=jsonb_build_object('participationId',v_updated.id,'conferenceId',v_updated.conference_id,
    'personId',v_updated.person_id,'status',v_updated.status,'revision',v_updated.revision,
    'guardianParticipationId',v_guardian.id,'guardianPersonId',v_guardian_person.id,
    'guardianFullName',v_guardian_person.full_name,'guardianParticipationStatus',v_guardian.status,
    'updatedAt',v_updated.updated_at,'updatedBy',v_updated.updated_by);
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at)
  values(v_actor,p_operation_id,'set_guardian',v_request,v_result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,
    entity_id,scope_type,old_values,new_values,metadata,operation_id,source)
  values(v_actor,v_device_authorization,'platform','conference','conference.participation.guardian_changed',
    'conference_participation',v_updated.id,'platform',
    jsonb_build_object('guardianParticipationId',v_child.guardian_participation_id,'revision',v_child.revision),
    jsonb_build_object('guardianParticipationId',v_updated.guardian_participation_id,'revision',v_updated.revision),
    jsonb_build_object('conferenceId',v_updated.conference_id,'permissionKey','conference.people.manage',
      'authoritySource',v_context->>'authoritySource','grantId',v_context->'grantId'),p_operation_id,'rpc');
  return v_result;
end $$;

-- Final public.get_conference_accommodation.
create or replace function public.get_conference_accommodation(p_device uuid,p_conference uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare context jsonb; result jsonb;
begin
  context:=platform_private.require_conference_accommodation_context(p_device,p_conference,'conference.accommodation.view',false);
  select coalesce(jsonb_agg(jsonb_build_object('houseId',h.id,'name',h.name,'description',h.description,'position',h.position,'revision',h.revision,'floors',
    (select coalesce(jsonb_agg(jsonb_build_object('floorId',f.id,'name',f.name,'position',f.position,'revision',f.revision,'rooms',
      (select coalesce(jsonb_agg(jsonb_build_object('roomId',r.id,'roomNumber',r.room_number,'baseCapacity',r.base_capacity,'extraBedCapacity',r.extra_bed_capacity,'notes',r.notes,'isClosed',r.is_closed,'closedDay',r.closed_day,'position',r.position,'revision',r.revision,'includedInPricing',not exists(select 1 from public.conference_accommodation_pricing_room_exclusions x where x.conference_id=r.conference_id and x.room_id=r.id),'occupancies',
        (select coalesce(jsonb_agg(jsonb_build_object('occupancyId',o.id,'revision',o.revision,'arrivalDay',o.arrival_day,'leaveDay',o.leave_day,'bedType',o.bed_type,'extraBedPersonType',o.extra_bed_person_type,'participationId',p.id,'participationStatus',p.status,
          'guardianParticipationId',guardian.id,'guardianPersonId',guardian_person.id,
          'guardianFullName',guardian_person.full_name,'guardianParticipationStatus',guardian.status,
          'person',jsonb_build_object('personId',pe.id,'fullName',pe.full_name,'phone',pe.phone,'gender',pe.gender,'dateOfBirth',pe.date_of_birth,'church',pe.church)) order by pe.full_name,o.id),'[]')
          from public.conference_accommodation_occupancies o
          join public.conference_participations p on p.id=o.participation_id
          join platform.people pe on pe.id=p.person_id
          left join public.conference_participations guardian on guardian.id=p.guardian_participation_id
          left join platform.people guardian_person on guardian_person.id=guardian.person_id
          where o.room_id=r.id)
      ) order by r.position,r.id),'[]') from public.conference_accommodation_rooms r where r.floor_id=f.id)
    ) order by f.position,f.id),'[]') from public.conference_accommodation_floors f where f.house_id=h.id)
  ) order by h.position,h.id),'[]') into result from public.conference_accommodation_houses h where h.conference_id=p_conference;
  return jsonb_build_object('conferenceId',p_conference,'houses',result,
    'pricing',platform_private.conference_accommodation_pricing_projection(p_conference));
end $$;

-- Final public.set_conference_participation_status.
create or replace function public.set_conference_participation_status(
  p_actor_device_id uuid,p_operation_id uuid,p_participation_id uuid,
  p_expected_revision bigint,p_status text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_current public.conference_participations%rowtype;
  v_updated public.conference_participations%rowtype;
  v_context jsonb; v_actor uuid; v_device_authorization uuid; v_request jsonb;
  v_prior public.conference_participation_operations%rowtype; v_result jsonb;
begin
  if p_operation_id is null or p_participation_id is null or p_expected_revision is null
     or p_expected_revision<1 or p_status not in('active','apologized') then
    raise exception 'CONFERENCE_PARTICIPATION_ARGUMENT_INVALID' using errcode='22023';
  end if;
  select * into v_current from public.conference_participations where id=p_participation_id;
  if not found then raise exception 'CONFERENCE_PARTICIPATION_NOT_FOUND' using errcode='P0002'; end if;
  v_context:=platform_private.require_conference_participation_context(
    p_actor_device_id,v_current.conference_id,'conference.people.manage',true);
  v_actor:=(v_context->>'actorUserId')::uuid;
  v_device_authorization:=platform_private.validated_phase1c_device_authorization(v_actor,p_actor_device_id);
  v_request:=jsonb_build_object('participationId',p_participation_id,'expectedRevision',p_expected_revision,'status',p_status);
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into v_prior from public.conference_participation_operations
  where actor_user_id=v_actor and operation_id=p_operation_id;
  if found then
    if v_prior.operation<>'set_status' or v_prior.request<>v_request then
      raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';
    end if;
    return v_prior.result;
  end if;
  select * into v_current from public.conference_participations where id=p_participation_id for update;
  if not found then raise exception 'CONFERENCE_PARTICIPATION_NOT_FOUND' using errcode='P0002'; end if;
  v_context:=platform_private.require_conference_participation_context(
    p_actor_device_id,v_current.conference_id,'conference.people.manage',true);
  if (v_context->>'actorUserId')::uuid is distinct from v_actor then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end if;
  if v_current.revision<>p_expected_revision then
    raise exception 'CONFERENCE_PARTICIPATION_REVISION_CONFLICT' using errcode='40001';
  end if;
  if v_current.status='active' and p_status='apologized' then
    perform platform_private.cleanup_conference_accommodation_for_participation(
      p_participation_id,v_actor,v_device_authorization,v_context,
      'participation_apologized',p_operation_id);
  end if;
  update public.conference_participations
  set status=p_status,revision=revision+1,updated_at=statement_timestamp(),updated_by=v_actor
  where id=p_participation_id returning * into v_updated;
  v_result:=jsonb_build_object(
    'participationId',v_updated.id,'conferenceId',v_updated.conference_id,
    'personId',v_updated.person_id,'status',v_updated.status,'revision',v_updated.revision,
    'updatedAt',v_updated.updated_at,'updatedBy',v_updated.updated_by);
  insert into public.conference_participation_operations
  values(v_actor,p_operation_id,'set_status',v_request,v_result,statement_timestamp());
  insert into platform.audit_events(
    actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,
    entity_id,scope_type,old_values,new_values,metadata,operation_id,source
  ) values(
    v_actor,v_device_authorization,'platform','conference','conference.participation.status_changed',
    'conference_participation',v_updated.id,'platform',
    jsonb_build_object('status',v_current.status,'revision',v_current.revision),
    jsonb_build_object('status',v_updated.status,'revision',v_updated.revision),
    jsonb_build_object(
      'conferenceId',v_updated.conference_id,'personId',v_updated.person_id,
      'permissionKey','conference.people.manage','authoritySource',v_context->>'authoritySource',
      'grantId',v_context->'grantId'),p_operation_id,'rpc');
  return v_result;
end $$;

-- Final public.assign_conference_accommodation.
create or replace function public.assign_conference_accommodation(
  p_device uuid,p_conference uuid,p_room uuid,p_participation uuid,
  p_arrival integer,p_leave integer,p_bed text,p_extra_type text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  context jsonb; actor uuid; device_authorization uuid;
  participation public.conference_participations%rowtype;
  room public.conference_accommodation_rooms%rowtype; days integer; used integer;
  row public.conference_accommodation_occupancies%rowtype; result jsonb;
begin
  context:=platform_private.require_conference_accommodation_context(p_device,p_conference,'conference.accommodation.manage',true);
  actor:=(context->>'actorUserId')::uuid;
  device_authorization:=platform_private.validated_phase1c_device_authorization(actor,p_device);
  days:=platform_private.conference_accommodation_duration(p_conference);
  if p_arrival<1 or p_arrival>days
     or (p_leave is not null and (p_leave<=p_arrival or p_leave>days+1)) then
    raise exception 'ACCOMMODATION_STAY_INVALID' using errcode='22023';
  end if;
  select * into participation from public.conference_participations
  where id=p_participation and conference_id=p_conference for update;
  if not found or participation.status<>'active' then
    raise exception 'ACTIVE_CONFERENCE_PARTICIPATION_REQUIRED' using errcode='42501';
  end if;
  select * into room from public.conference_accommodation_rooms
  where id=p_room and conference_id=p_conference for update;
  if not found then raise exception 'ACCOMMODATION_ROOM_NOT_FOUND' using errcode='P0002'; end if;
  if room.is_closed and (room.closed_day is null or p_arrival>=room.closed_day
     or coalesce(p_leave,days+1)>room.closed_day) then
    raise exception 'ACCOMMODATION_ROOM_UNAVAILABLE' using errcode='55000';
  end if;
  select count(*) into used from public.conference_accommodation_occupancies
  where room_id=p_room and bed_type=p_bed
    and arrival_day<coalesce(p_leave,days+1) and p_arrival<coalesce(leave_day,days+1);
  if (p_bed='base' and used>=room.base_capacity)
     or (p_bed='extra' and used>=room.extra_bed_capacity) then
    raise exception 'ACCOMMODATION_ROOM_CAPACITY_EXCEEDED' using errcode='55000';
  end if;
  insert into public.conference_accommodation_occupancies(
    conference_id,room_id,participation_id,arrival_day,leave_day,bed_type,
    extra_bed_person_type,created_by,updated_by
  ) values(p_conference,p_room,p_participation,p_arrival,p_leave,p_bed,p_extra_type,actor,actor)
  returning * into row;
  result:=jsonb_build_object(
    'occupancyId',row.id,'revision',row.revision,'roomId',row.room_id,
    'participationId',row.participation_id);
  insert into platform.audit_events(
    actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,
    entity_id,scope_type,new_values,metadata,source
  ) values(
    actor,device_authorization,'platform','conference','conference.accommodation.assigned',
    'accommodation_occupancy',row.id,'platform',to_jsonb(row),
    jsonb_build_object(
      'conferenceId',p_conference,'participationId',p_participation,
      'permissionKey','conference.accommodation.manage','authoritySource',context->>'authoritySource',
      'grantId',context->'grantId'),'rpc');
  return result;
end $$;

-- Final public.move_conference_accommodation.
create or replace function public.move_conference_accommodation(
  p_device uuid,p_conference uuid,p_occupancy uuid,p_expected bigint,p_room uuid,
  p_arrival integer,p_leave integer,p_bed text,p_extra_type text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  context jsonb; actor uuid; device_authorization uuid;
  participation public.conference_participations%rowtype;
  current public.conference_accommodation_occupancies%rowtype;
  destination public.conference_accommodation_rooms%rowtype;
  days integer; used integer; updated public.conference_accommodation_occupancies%rowtype;
begin
  context:=platform_private.require_conference_accommodation_context(p_device,p_conference,'conference.accommodation.manage',true);
  actor:=(context->>'actorUserId')::uuid;
  device_authorization:=platform_private.validated_phase1c_device_authorization(actor,p_device);
  days:=platform_private.conference_accommodation_duration(p_conference);
  if p_arrival<1 or p_arrival>days
     or (p_leave is not null and (p_leave<=p_arrival or p_leave>days+1)) then
    raise exception 'ACCOMMODATION_STAY_INVALID' using errcode='22023';
  end if;
  select * into current from public.conference_accommodation_occupancies
  where id=p_occupancy and conference_id=p_conference;
  if not found then raise exception 'ACCOMMODATION_OCCUPANCY_NOT_FOUND' using errcode='P0002'; end if;
  select * into participation from public.conference_participations
  where id=current.participation_id and conference_id=p_conference for update;
  if not found or participation.status<>'active' then
    raise exception 'ACTIVE_CONFERENCE_PARTICIPATION_REQUIRED' using errcode='42501';
  end if;
  select * into current from public.conference_accommodation_occupancies
  where id=p_occupancy and conference_id=p_conference;
  if not found or current.participation_id<>participation.id then
    raise exception 'ACCOMMODATION_OCCUPANCY_NOT_FOUND' using errcode='P0002';
  end if;
  perform 1 from public.conference_accommodation_rooms
  where id in(current.room_id,p_room) order by id for update;
  select * into current from public.conference_accommodation_occupancies
  where id=p_occupancy and participation_id=participation.id for update;
  if not found then raise exception 'ACCOMMODATION_OCCUPANCY_NOT_FOUND' using errcode='P0002'; end if;
  if current.revision<>p_expected then
    raise exception 'ACCOMMODATION_REVISION_CONFLICT' using errcode='40001';
  end if;
  select * into destination from public.conference_accommodation_rooms
  where id=p_room and conference_id=p_conference;
  if not found then raise exception 'ACCOMMODATION_ROOM_NOT_FOUND' using errcode='P0002'; end if;
  if destination.is_closed and (destination.closed_day is null or p_arrival>=destination.closed_day
     or coalesce(p_leave,days+1)>destination.closed_day) then
    raise exception 'ACCOMMODATION_ROOM_UNAVAILABLE' using errcode='55000';
  end if;
  select count(*) into used from public.conference_accommodation_occupancies
  where room_id=p_room and bed_type=p_bed and id<>p_occupancy
    and arrival_day<coalesce(p_leave,days+1) and p_arrival<coalesce(leave_day,days+1);
  if (p_bed='base' and used>=destination.base_capacity)
     or (p_bed='extra' and used>=destination.extra_bed_capacity) then
    raise exception 'ACCOMMODATION_ROOM_CAPACITY_EXCEEDED' using errcode='55000';
  end if;
  update public.conference_accommodation_occupancies
  set room_id=p_room,arrival_day=p_arrival,leave_day=p_leave,bed_type=p_bed,
      extra_bed_person_type=p_extra_type,revision=revision+1,
      updated_at=statement_timestamp(),updated_by=actor
  where id=p_occupancy returning * into updated;
  insert into platform.audit_events(
    actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,
    entity_id,scope_type,old_values,new_values,metadata,source
  ) values(
    actor,device_authorization,'platform','conference','conference.accommodation.moved',
    'accommodation_occupancy',p_occupancy,'platform',to_jsonb(current),to_jsonb(updated),
    jsonb_build_object(
      'conferenceId',p_conference,'participationId',current.participation_id,
      'oldRoomId',current.room_id,'newRoomId',p_room,
      'permissionKey','conference.accommodation.manage','authoritySource',context->>'authoritySource',
      'grantId',context->'grantId'),'rpc');
  return jsonb_build_object('occupancyId',updated.id,'revision',updated.revision,'roomId',updated.room_id);
end $$;

-- Final public.delete_conference_participation.
create or replace function public.delete_conference_participation(p_actor_device_id uuid,p_operation_id uuid,p_participation_id uuid,p_expected_revision bigint) returns jsonb language plpgsql security definer set search_path='' as $$ declare ctx jsonb;actor uuid;authz uuid;prior public.conference_participation_operations%rowtype;r public.conference_restaurant_participation_overrides%rowtype;result jsonb;begin
  ctx:=nullif(current_setting('platform.phase1c_context',true),'')::jsonb;actor:=(ctx->>'user_id')::uuid;if ctx->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or (ctx->>'device_id')::uuid is distinct from p_actor_device_id then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;authz:=platform_private.validated_phase1c_device_authorization(actor,p_actor_device_id);if authz is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':conference-participation:'||p_operation_id::text,0));select * into prior from public.conference_participation_operations where actor_user_id=actor and operation_id=p_operation_id;if found then if prior.operation<>'delete' or prior.request<>jsonb_build_object('participationId',p_participation_id,'expectedRevision',p_expected_revision) then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';end if;perform platform_private.require_conference_participation_context(p_actor_device_id,(prior.result->>'conferenceId')::uuid,'conference.people.manage',false);return prior.result;end if;
  for r in select o.* from public.conference_restaurant_participation_overrides o join public.conference_participations p on p.id=o.participation_id where p.id=p_participation_id or p.guardian_participation_id=p_participation_id order by o.id for update loop
    insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source) values(actor,authz,'platform','conference','conference.restaurant.participation_override_removed','conference_restaurant_participation_override',r.id,'platform',to_jsonb(r),null,jsonb_build_object('conferenceId',r.conference_id,'reason','participation_deleted','permissionKey','conference.people.manage'),p_operation_id,'rpc');delete from public.conference_restaurant_participation_overrides where id=r.id;
  end loop;
  result:=public.delete_conference_participation_without_restaurant_cleanup(p_actor_device_id,p_operation_id,p_participation_id,p_expected_revision);return result;
end $$;

-- Final platform_private.require_conference_restaurant_context.
create or replace function platform_private.require_conference_restaurant_context(p_device uuid,p_conference uuid,p_permission text,p_mutation boolean)
returns jsonb language plpgsql stable security definer set search_path='' as $$ declare c jsonb; actor uuid; conf public.conferences%rowtype; begin
  if p_permission not in('conference.restaurant.view','conference.restaurant.manage') then raise exception 'CONFERENCE_RESTAURANT_ARGUMENT_INVALID' using errcode='22023';end if;
  c:=public.require_effective_module_permission(p_device,'conference',p_permission,'conference',p_conference::text);actor:=(c->>'actorUserId')::uuid;
  if platform_private.validated_phase1c_device_authorization(actor,p_device) is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
  select * into conf from public.conferences where id=p_conference and deleted_at is null;if not found then raise exception 'CONFERENCE_NOT_FOUND' using errcode='P0002';end if;
  if p_mutation and conf.status<>'active' then raise exception 'COMPLETED_CONFERENCE_IMMUTABLE' using errcode='55000';end if;return c;
end $$;

-- Final public.get_conference_restaurant.
create or replace function public.get_conference_restaurant(p_device uuid,p_conference uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$ declare c jsonb;s public.conference_restaurant_settings%rowtype;can_manage boolean:=false;begin
  c:=platform_private.require_conference_restaurant_context(p_device,p_conference,'conference.restaurant.view',false);
  begin perform public.require_effective_module_permission(p_device,'conference','conference.restaurant.manage','conference',p_conference::text);can_manage:=true;exception when insufficient_privilege then null;end;
  select * into s from public.conference_restaurant_settings where conference_id=p_conference;
  return jsonb_build_object('conferenceId',p_conference,'canManage',can_manage,'settings',jsonb_build_object('enabled',coalesce(s.enabled,true),'firstMeal',coalesce(s.first_meal,'dinner'),'lastMeal',coalesce(s.last_meal,'lunch'),'prices',jsonb_build_object('breakfast',coalesce(s.breakfast_price,0),'lunch',coalesce(s.lunch_price,0),'dinner',coalesce(s.dinner_price,0)),'revision',coalesce(s.revision,0)),
    'priceOverrides',coalesce((select jsonb_agg(jsonb_build_object('id',id,'day',day_number,'meal',meal,'price',price,'revision',revision) order by day_number,meal) from public.conference_restaurant_price_overrides where conference_id=p_conference),'[]'),
    'countOverrides',coalesce((select jsonb_agg(jsonb_build_object('id',id,'day',day_number,'meal',meal,'extra',extra_count,'deduction',deduction_count,'note',note,'revision',revision) order by day_number,meal) from public.conference_restaurant_count_overrides where conference_id=p_conference),'[]'),
    'participationOverrides',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'participationId',o.participation_id,'day',o.day_number,'meal',o.meal,'included',o.included,'note',o.note,'revision',o.revision) order by o.day_number,o.meal,o.participation_id) from public.conference_restaurant_participation_overrides o where o.conference_id=p_conference),'[]'),
    'participations',coalesce((select jsonb_agg(jsonb_build_object('participationId',p.id,'status',p.status,'person',jsonb_build_object('personId',person.id,'fullName',person.full_name,'phone',person.phone),'roomNumber',room.room_number) order by person.full_name,p.id) from public.conference_participations p join platform.people person on person.id=p.person_id left join public.conference_accommodation_occupancies occupancy on occupancy.participation_id=p.id left join public.conference_accommodation_rooms room on room.id=occupancy.room_id where p.conference_id=p_conference),'[]'));
end $$;

-- Final public.mutate_conference_restaurant.
create or replace function public.mutate_conference_restaurant(p_device uuid,p_operation_id uuid,p_operation text,p_conference uuid,p_expected_revision bigint,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$ declare c jsonb;actor uuid;authz uuid;req jsonb;prior public.conference_participation_operations%rowtype;old jsonb;result jsonb;entity uuid;rev bigint;maximum_day integer;begin
  if p_operation_id is null or p_operation not in('update_settings','upsert_price','delete_price','upsert_count','delete_count','upsert_participation','delete_participation') or jsonb_typeof(p_payload)<>'object' then raise exception 'CONFERENCE_RESTAURANT_ARGUMENT_INVALID' using errcode='22023';end if;
  c:=platform_private.require_conference_restaurant_context(p_device,p_conference,'conference.restaurant.manage',true);actor:=(c->>'actorUserId')::uuid;authz:=platform_private.validated_phase1c_device_authorization(actor,p_device);req:=jsonb_build_object('operation',p_operation,'conferenceId',p_conference,'expectedRevision',p_expected_revision,'payload',p_payload);
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':conference-participation:'||p_operation_id::text,0));select * into prior from public.conference_participation_operations where actor_user_id=actor and operation_id=p_operation_id;
  if found then if prior.operation<>'restaurant_mutation' or prior.request<>req then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';end if;return prior.result;end if;
  if p_operation='update_settings' then
    perform platform_private.require_exact_jsonb_keys(p_payload,array['enabled','firstMeal','lastMeal','prices']);perform platform_private.require_exact_jsonb_keys(p_payload->'prices',array['breakfast','lunch','dinner']);
    insert into public.conference_restaurant_settings(conference_id,enabled,first_meal,last_meal,breakfast_price,lunch_price,dinner_price,created_by,updated_by) values(p_conference,coalesce((p_payload->>'enabled')::boolean,true),p_payload->>'firstMeal',p_payload->>'lastMeal',(p_payload->'prices'->>'breakfast')::numeric,(p_payload->'prices'->>'lunch')::numeric,(p_payload->'prices'->>'dinner')::numeric,actor,actor)
    on conflict(conference_id) do update set enabled=excluded.enabled,first_meal=excluded.first_meal,last_meal=excluded.last_meal,breakfast_price=excluded.breakfast_price,lunch_price=excluded.lunch_price,dinner_price=excluded.dinner_price,revision=conference_restaurant_settings.revision+1,updated_at=statement_timestamp(),updated_by=actor where p_expected_revision=conference_restaurant_settings.revision returning conference_id,revision into entity,rev;
  elsif p_operation like '%price' then
    perform platform_private.require_exact_jsonb_keys(p_payload,case when p_operation='upsert_price' then array['day','meal','price'] else array['day','meal'] end);select (end_date-start_date)+1 into maximum_day from public.conferences where id=p_conference;if (p_payload->>'day')::integer not between 1 and maximum_day then raise exception 'CONFERENCE_RESTAURANT_DAY_INVALID' using errcode='22023';end if;
    select to_jsonb(x),x.id,x.revision into old,entity,rev from public.conference_restaurant_price_overrides x where conference_id=p_conference and day_number=(p_payload->>'day')::integer and meal=p_payload->>'meal' for update;
    if p_operation='delete_price' then if entity is null then raise exception 'CONFERENCE_RESTAURANT_NOT_FOUND' using errcode='P0002';end if;if rev<>p_expected_revision then raise exception 'CONFERENCE_RESTAURANT_REVISION_CONFLICT' using errcode='40001';end if;delete from public.conference_restaurant_price_overrides where id=entity;
    elsif entity is null then insert into public.conference_restaurant_price_overrides(conference_id,day_number,meal,price,created_by,updated_by) values(p_conference,(p_payload->>'day')::integer,p_payload->>'meal',(p_payload->>'price')::numeric,actor,actor) returning id,revision into entity,rev;
    else if rev<>p_expected_revision then raise exception 'CONFERENCE_RESTAURANT_REVISION_CONFLICT' using errcode='40001';end if;update public.conference_restaurant_price_overrides set price=(p_payload->>'price')::numeric,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=entity returning revision into rev;end if;
  elsif p_operation like '%count' then
    perform platform_private.require_exact_jsonb_keys(p_payload,case when p_operation='upsert_count' then array['day','meal','extra','deduction','note'] else array['day','meal'] end);select (end_date-start_date)+1 into maximum_day from public.conferences where id=p_conference;if (p_payload->>'day')::integer not between 1 and maximum_day then raise exception 'CONFERENCE_RESTAURANT_DAY_INVALID' using errcode='22023';end if;
    select to_jsonb(x),x.id,x.revision into old,entity,rev from public.conference_restaurant_count_overrides x where conference_id=p_conference and day_number=(p_payload->>'day')::integer and meal=p_payload->>'meal' for update;
    if p_operation='delete_count' then if entity is null then raise exception 'CONFERENCE_RESTAURANT_NOT_FOUND' using errcode='P0002';end if;if rev<>p_expected_revision then raise exception 'CONFERENCE_RESTAURANT_REVISION_CONFLICT' using errcode='40001';end if;delete from public.conference_restaurant_count_overrides where id=entity;
    elsif entity is null then insert into public.conference_restaurant_count_overrides(conference_id,day_number,meal,extra_count,deduction_count,note,created_by,updated_by) values(p_conference,(p_payload->>'day')::integer,p_payload->>'meal',(p_payload->>'extra')::integer,(p_payload->>'deduction')::integer,nullif(p_payload->>'note',''),actor,actor) returning id,revision into entity,rev;
    else if rev<>p_expected_revision then raise exception 'CONFERENCE_RESTAURANT_REVISION_CONFLICT' using errcode='40001';end if;update public.conference_restaurant_count_overrides set extra_count=(p_payload->>'extra')::integer,deduction_count=(p_payload->>'deduction')::integer,note=nullif(p_payload->>'note',''),revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=entity returning revision into rev;end if;
  else
    perform platform_private.require_exact_jsonb_keys(p_payload,case when p_operation='upsert_participation' then array['participationId','day','meal','included','note'] else array['participationId','day','meal'] end);select (end_date-start_date)+1 into maximum_day from public.conferences where id=p_conference;if (p_payload->>'day')::integer not between 1 and maximum_day or not exists(select 1 from public.conference_participations where id=(p_payload->>'participationId')::uuid and conference_id=p_conference and status='active') then raise exception 'CONFERENCE_RESTAURANT_PARTICIPATION_INELIGIBLE' using errcode='23514';end if;
    select to_jsonb(x),x.id,x.revision into old,entity,rev from public.conference_restaurant_participation_overrides x where conference_id=p_conference and participation_id=(p_payload->>'participationId')::uuid and day_number=(p_payload->>'day')::integer and meal=p_payload->>'meal' for update;
    if p_operation='delete_participation' then if entity is null then raise exception 'CONFERENCE_RESTAURANT_NOT_FOUND' using errcode='P0002';end if;if rev<>p_expected_revision then raise exception 'CONFERENCE_RESTAURANT_REVISION_CONFLICT' using errcode='40001';end if;delete from public.conference_restaurant_participation_overrides where id=entity;
    elsif entity is null then insert into public.conference_restaurant_participation_overrides(conference_id,participation_id,day_number,meal,included,note,created_by,updated_by) values(p_conference,(p_payload->>'participationId')::uuid,(p_payload->>'day')::integer,p_payload->>'meal',(p_payload->>'included')::boolean,nullif(p_payload->>'note',''),actor,actor) returning id,revision into entity,rev;
    else if rev<>p_expected_revision then raise exception 'CONFERENCE_RESTAURANT_REVISION_CONFLICT' using errcode='40001';end if;update public.conference_restaurant_participation_overrides set included=(p_payload->>'included')::boolean,note=nullif(p_payload->>'note',''),revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=entity returning revision into rev;end if;
  end if;
  if entity is null then raise exception 'CONFERENCE_RESTAURANT_REVISION_CONFLICT' using errcode='40001';end if;result:=jsonb_build_object('conferenceId',p_conference,'entityId',entity,'operation',p_operation,'revision',rev,'deleted',p_operation like 'delete_%');
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at) values(actor,p_operation_id,'restaurant_mutation',req,result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source) values(actor,authz,'platform','conference','conference.restaurant.'||p_operation,'conference_restaurant_fact',entity,'platform',old,case when p_operation like 'delete_%' then null else p_payload end,jsonb_build_object('conferenceId',p_conference,'permissionKey','conference.restaurant.manage'),p_operation_id,'rpc');return result;
end $$;

-- Final platform_private.require_conference_accommodation_context.
create or replace function platform_private.require_conference_accommodation_context(p_device uuid,p_conference uuid,p_permission text,p_mutation boolean)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.conferences%rowtype; context jsonb; actor uuid;
begin
  if p_permission not in('conference.accommodation.view','conference.accommodation.manage') then raise exception 'ACCOMMODATION_ARGUMENT_INVALID' using errcode='22023'; end if;
  context:=public.require_effective_module_permission(p_device,'conference',p_permission,'conference',p_conference::text); actor:=(context->>'actorUserId')::uuid;
  if platform_private.validated_phase1c_device_authorization(actor,p_device) is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  select * into c from public.conferences where id=p_conference;
  if not found or c.deleted_at is not null then raise exception 'CONFERENCE_NOT_FOUND' using errcode='P0002'; end if;
  if p_mutation and c.status<>'active' then raise exception 'COMPLETED_CONFERENCE_IMMUTABLE' using errcode='55000'; end if;
  return context;
end $$;

-- Final platform_private.conference_accommodation_duration.
create or replace function platform_private.conference_accommodation_duration(p_conference uuid)
returns integer language plpgsql stable security definer set search_path='' as $$
declare days integer;
begin
  select end_date-start_date+1 into days from public.conferences where id=p_conference and start_date is not null and end_date is not null and end_date>=start_date;
  if days is null then raise exception 'CONFERENCE_DURATION_REQUIRED' using errcode='22023'; end if; return days;
end $$;

-- Final public.mutate_conference_accommodation_structure.
create or replace function public.mutate_conference_accommodation_structure(p_device uuid,p_operation text,p_args jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare conference uuid:=(p_args->>'p_conference_id')::uuid; context jsonb; actor uuid; device_authorization uuid; v_id uuid; v_expected bigint; v_old jsonb; v_result jsonb; days integer; v_parent uuid;
begin
  context:=platform_private.require_conference_accommodation_context(p_device,conference,'conference.accommodation.manage',true); actor:=(context->>'actorUserId')::uuid; device_authorization:=platform_private.validated_phase1c_device_authorization(actor,p_device);
  if p_operation='create_house' then
    insert into public.conference_accommodation_houses(conference_id,name,description,position,created_by,updated_by) values(conference,p_args->>'p_name',p_args->>'p_description',coalesce((p_args->>'p_position')::integer,0),actor,actor) returning conference_accommodation_houses.id into v_id; v_result:=jsonb_build_object('houseId',v_id,'revision',1);
  elsif p_operation='update_house' then
    v_id:=(p_args->>'p_house_id')::uuid; v_expected:=(p_args->>'p_expected_revision')::bigint; select to_jsonb(h) into v_old from public.conference_accommodation_houses h where h.id=v_id and h.conference_id=conference for update;
    if v_old is null then raise exception 'ACCOMMODATION_HOUSE_NOT_FOUND' using errcode='P0002'; end if; if (v_old->>'revision')::bigint<>v_expected then raise exception 'ACCOMMODATION_REVISION_CONFLICT' using errcode='40001'; end if;
    update public.conference_accommodation_houses set name=p_args->>'p_name',description=p_args->>'p_description',position=(p_args->>'p_position')::integer,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where conference_id=conference and public.conference_accommodation_houses.id=v_id returning jsonb_build_object('houseId',v_id,'revision',revision) into v_result;
  elsif p_operation='delete_house' then
    v_id:=(p_args->>'p_house_id')::uuid; v_expected:=(p_args->>'p_expected_revision')::bigint; select to_jsonb(h) into v_old from public.conference_accommodation_houses h where h.id=v_id and h.conference_id=conference for update;
    if v_old is null then raise exception 'ACCOMMODATION_HOUSE_NOT_FOUND' using errcode='P0002'; end if; if (v_old->>'revision')::bigint<>v_expected then raise exception 'ACCOMMODATION_REVISION_CONFLICT' using errcode='40001'; end if; if exists(select 1 from public.conference_accommodation_floors where house_id=v_id) then raise exception 'ACCOMMODATION_HOUSE_NOT_EMPTY' using errcode='55000'; end if; delete from public.conference_accommodation_houses where public.conference_accommodation_houses.id=v_id; v_result:=jsonb_build_object('houseId',v_id,'deleted',true);
  elsif p_operation='create_floor' then
    v_parent:=(p_args->>'p_house_id')::uuid; if not exists(select 1 from public.conference_accommodation_houses where id=v_parent and conference_id=conference) then raise exception 'ACCOMMODATION_HOUSE_NOT_FOUND' using errcode='P0002'; end if;
    insert into public.conference_accommodation_floors(conference_id,house_id,name,position,created_by,updated_by) values(conference,v_parent,p_args->>'p_name',coalesce((p_args->>'p_position')::integer,0),actor,actor) returning conference_accommodation_floors.id into v_id; v_result:=jsonb_build_object('floorId',v_id,'revision',1);
  elsif p_operation in('update_floor','delete_floor') then
    v_id:=(p_args->>'p_floor_id')::uuid; v_expected:=(p_args->>'p_expected_revision')::bigint; select to_jsonb(f) into v_old from public.conference_accommodation_floors f where f.id=v_id and f.conference_id=conference for update;
    if v_old is null then raise exception 'ACCOMMODATION_FLOOR_NOT_FOUND' using errcode='P0002'; end if; if (v_old->>'revision')::bigint<>v_expected then raise exception 'ACCOMMODATION_REVISION_CONFLICT' using errcode='40001'; end if;
    if p_operation='update_floor' then update public.conference_accommodation_floors set name=p_args->>'p_name',position=(p_args->>'p_position')::integer,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where public.conference_accommodation_floors.id=v_id returning jsonb_build_object('floorId',v_id,'revision',revision) into v_result; else if exists(select 1 from public.conference_accommodation_rooms where floor_id=v_id) then raise exception 'ACCOMMODATION_FLOOR_NOT_EMPTY' using errcode='55000'; end if; delete from public.conference_accommodation_floors where public.conference_accommodation_floors.id=v_id; v_result:=jsonb_build_object('floorId',v_id,'deleted',true); end if;
  elsif p_operation='create_room' then
    v_parent:=(p_args->>'p_floor_id')::uuid; if not exists(select 1 from public.conference_accommodation_floors where id=v_parent and conference_id=conference) then raise exception 'ACCOMMODATION_FLOOR_NOT_FOUND' using errcode='P0002'; end if; if p_args->>'p_closed_day' is not null then days:=platform_private.conference_accommodation_duration(conference); if (p_args->>'p_closed_day')::integer>days then raise exception 'ACCOMMODATION_DAY_OUT_OF_RANGE' using errcode='22023'; end if; end if;
    insert into public.conference_accommodation_rooms(conference_id,floor_id,room_number,base_capacity,extra_bed_capacity,notes,is_closed,closed_day,position,created_by,updated_by) values(conference,v_parent,p_args->>'p_room_number',(p_args->>'p_base_capacity')::integer,(p_args->>'p_extra_bed_capacity')::integer,p_args->>'p_notes',(p_args->>'p_is_closed')::boolean,(p_args->>'p_closed_day')::integer,coalesce((p_args->>'p_position')::integer,0),actor,actor) returning conference_accommodation_rooms.id into v_id; v_result:=jsonb_build_object('roomId',v_id,'revision',1);
  elsif p_operation in('update_room','delete_room') then
    v_id:=(p_args->>'p_room_id')::uuid; v_expected:=(p_args->>'p_expected_revision')::bigint; select to_jsonb(r) into v_old from public.conference_accommodation_rooms r where r.id=v_id and r.conference_id=conference for update;
    if v_old is null then raise exception 'ACCOMMODATION_ROOM_NOT_FOUND' using errcode='P0002'; end if; if (v_old->>'revision')::bigint<>v_expected then raise exception 'ACCOMMODATION_REVISION_CONFLICT' using errcode='40001'; end if;
    if p_operation='delete_room' then if exists(select 1 from public.conference_accommodation_occupancies where room_id=v_id) then raise exception 'ACCOMMODATION_ROOM_OCCUPIED' using errcode='55000'; end if; delete from public.conference_accommodation_rooms where public.conference_accommodation_rooms.id=v_id; v_result:=jsonb_build_object('roomId',v_id,'deleted',true);
    else if p_args->>'p_closed_day' is not null then days:=platform_private.conference_accommodation_duration(conference); if (p_args->>'p_closed_day')::integer>days then raise exception 'ACCOMMODATION_DAY_OUT_OF_RANGE' using errcode='22023'; end if; end if; -- Evaluate simultaneous use on each Conference day, independently by bed type.
      -- Preserve undated empty-room edits: duration is needed only with occupancies.
      if exists(select 1 from public.conference_accommodation_occupancies where room_id=v_id) then
        days:=platform_private.conference_accommodation_duration(conference);
        if exists(
          select 1 from generate_series(1,days) as stay_day(day)
          join public.conference_accommodation_occupancies o on o.room_id=v_id
            and o.arrival_day<=stay_day.day and stay_day.day<coalesce(o.leave_day,days+1)
          group by stay_day.day
          having count(*) filter(where o.bed_type='base')>(p_args->>'p_base_capacity')::integer
              or count(*) filter(where o.bed_type='extra')>(p_args->>'p_extra_bed_capacity')::integer
        ) then raise exception 'ACCOMMODATION_CAPACITY_CONFLICT' using errcode='55000'; end if;
      end if; if (p_args->>'p_is_closed')::boolean and exists(select 1 from public.conference_accommodation_occupancies where room_id=v_id and ((p_args->>'p_closed_day') is null or arrival_day>=(p_args->>'p_closed_day')::integer or coalesce(leave_day,days+1)>(p_args->>'p_closed_day')::integer)) then raise exception 'ACCOMMODATION_CLOSURE_CONFLICT' using errcode='55000'; end if;
      update public.conference_accommodation_rooms set room_number=p_args->>'p_room_number',base_capacity=(p_args->>'p_base_capacity')::integer,extra_bed_capacity=(p_args->>'p_extra_bed_capacity')::integer,notes=p_args->>'p_notes',is_closed=(p_args->>'p_is_closed')::boolean,closed_day=(p_args->>'p_closed_day')::integer,position=(p_args->>'p_position')::integer,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where public.conference_accommodation_rooms.id=v_id returning jsonb_build_object('roomId',v_id,'revision',revision) into v_result; end if;
  else raise exception 'ACCOMMODATION_OPERATION_INVALID' using errcode='22023'; end if;
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,source) values(actor,device_authorization,'platform','conference','conference.accommodation.'||p_operation,'accommodation_structure',v_id,'platform',v_old,v_result,jsonb_build_object('conferenceId',conference,'permissionKey','conference.accommodation.manage','authoritySource',context->>'authoritySource','grantId',context->'grantId'),'rpc'); return v_result;
end $$;

-- Final public.remove_conference_accommodation.
create or replace function public.remove_conference_accommodation(p_device uuid,p_conference uuid,p_occupancy uuid,p_expected bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare context jsonb; actor uuid; device_authorization uuid; current public.conference_accommodation_occupancies%rowtype;
begin
 context:=platform_private.require_conference_accommodation_context(p_device,p_conference,'conference.accommodation.manage',true); actor:=(context->>'actorUserId')::uuid; device_authorization:=platform_private.validated_phase1c_device_authorization(actor,p_device); select * into current from public.conference_accommodation_occupancies where id=p_occupancy and conference_id=p_conference for update; if not found then raise exception 'ACCOMMODATION_OCCUPANCY_NOT_FOUND' using errcode='P0002'; end if; if current.revision<>p_expected then raise exception 'ACCOMMODATION_REVISION_CONFLICT' using errcode='40001'; end if;
 delete from public.conference_accommodation_occupancies where id=p_occupancy; insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,metadata,source) values(actor,device_authorization,'platform','conference','conference.accommodation.removed','accommodation_occupancy',p_occupancy,'platform',to_jsonb(current),jsonb_build_object('conferenceId',p_conference,'participationId',current.participation_id,'permissionKey','conference.accommodation.manage','authoritySource',context->>'authoritySource','grantId',context->'grantId'),'rpc'); return jsonb_build_object('occupancyId',p_occupancy,'deleted',true);
end $$;

-- Final public.get_conference_core.
create or replace function public.get_conference_core(
  p_actor_device_id uuid,
  p_conference_id uuid
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_context jsonb;
  v_actor uuid;
  v_conference public.conferences%rowtype;
  v_schedule jsonb;
begin
  if p_conference_id is null then
    raise exception 'CONFERENCE_CORE_ARGUMENT_INVALID' using errcode='22023';
  end if;
  v_context:=public.require_effective_module_permission(
    p_actor_device_id,'conference','conference.access.view',
    'conference',p_conference_id::text
  );
  v_actor:=(v_context->>'actorUserId')::uuid;
  if platform_private.validated_phase1c_device_authorization(
    v_actor,p_actor_device_id
  ) is null then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end if;
  select conferences.* into v_conference
  from public.conferences conferences
  where conferences.id=p_conference_id and conferences.deleted_at is null;
  if not found then
    raise exception 'CONFERENCE_CORE_NOT_FOUND' using errcode='P0002';
  end if;
  select coalesce(
    jsonb_agg(to_jsonb(schedule_day::date) order by schedule_day),'[]'::jsonb
  ) into v_schedule
  from generate_series(
    v_conference.start_date::timestamp,v_conference.end_date::timestamp,
    interval '1 day'
  ) schedule_day;
  return jsonb_build_object(
    'conferenceId',v_conference.id,
    'organizationId',v_conference.organization_id,
    'name',v_conference.name,
    'place',v_conference.place,
    'startDate',v_conference.start_date,
    'endDate',v_conference.end_date,
    'status',v_conference.status,
    'completedAt',v_conference.completed_at,
    'revision',v_conference.revision,
    'createdAt',v_conference.created_at,
    'updatedAt',v_conference.updated_at,
    'updatedBy',v_conference.updated_by,
    'days',case when v_conference.start_date is null then null
      else (v_conference.end_date-v_conference.start_date)+1 end,
    'nights',case when v_conference.start_date is null then null
      else v_conference.end_date-v_conference.start_date end,
    'schedule',v_schedule
  );
end $$;

-- Final public.mutate_conference_core.
create or replace function public.mutate_conference_core(
  p_actor_device_id uuid,p_operation_id uuid,p_conference_id uuid,
  p_expected_revision bigint,p_name text,p_place text,
  p_start_date date,p_end_date date,p_status text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare ctx jsonb; session_ctx jsonb; actor uuid; authz uuid;
  prior public.conference_participation_operations%rowtype;
  current_row public.conferences%rowtype; changed public.conferences%rowtype;
  req jsonb; result jsonb; schedule jsonb; clean_name text:=btrim(coalesce(p_name,''));
  clean_place text:=btrim(coalesce(p_place,'')); completed timestamptz;
begin
  if p_operation_id is null or p_conference_id is null or p_expected_revision is null
     or p_expected_revision<1 or clean_name='' or char_length(clean_name)>500
     or char_length(clean_place)>500 or p_start_date is null or p_end_date is null
     or p_end_date<p_start_date or p_status not in('active','completed') then
    raise exception 'CONFERENCE_CORE_ARGUMENT_INVALID' using errcode='22023';
  end if;
  session_ctx:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;
  actor:=(session_ctx->>'user_id')::uuid;
  if session_ctx->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH'
     or (session_ctx->>'device_id')::uuid is distinct from p_actor_device_id then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end if;
  authz:=platform_private.validated_phase1c_device_authorization(actor,p_actor_device_id);
  if authz is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  ctx:=public.require_effective_module_permission(p_actor_device_id,'conference',
    'conference.lifecycle.manage','conference',p_conference_id::text);
  if (ctx->>'actorUserId')::uuid is distinct from actor then
    raise exception 'ACTOR_DEVICE_OVERRIDE_DENIED' using errcode='42501';
  end if;
  req:=jsonb_build_object('conferenceId',p_conference_id,'expectedRevision',p_expected_revision,
    'name',clean_name,'place',clean_place,'startDate',p_start_date,
    'endDate',p_end_date,'status',p_status);
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into prior from public.conference_participation_operations
    where actor_user_id=actor and operation_id=p_operation_id;
  if found then
    if prior.operation<>'conference_core_mutation' or prior.request<>req then
      raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';
    end if;
    return prior.result;
  end if;
  select * into current_row from public.conferences where id=p_conference_id for update;
  if not found or current_row.deleted_at is not null then raise exception 'CONFERENCE_CORE_NOT_FOUND' using errcode='P0002'; end if;
  if current_row.revision<>p_expected_revision then raise exception 'CONFERENCE_CORE_REVISION_CONFLICT' using errcode='40001'; end if;
  if current_row.status='completed' then raise exception 'CONFERENCE_LIFECYCLE_TRANSITION_INVALID' using errcode='55000'; end if;
  completed:=case when p_status='completed' then statement_timestamp() else null end;
  update public.conferences c set name=clean_name,place=clean_place,start_date=p_start_date,
    end_date=p_end_date,status=p_status,completed_at=completed,revision=c.revision+1,
    updated_by=actor,updated_at=statement_timestamp() where c.id=p_conference_id returning c.* into changed;
  select coalesce(jsonb_agg(to_jsonb(day::date) order by day),'[]'::jsonb) into schedule
    from generate_series(p_start_date::timestamp,p_end_date::timestamp,interval '1 day') day;
  result:=jsonb_build_object('conferenceId',changed.id,'name',changed.name,'place',changed.place,
    'startDate',changed.start_date,'endDate',changed.end_date,'status',changed.status,
    'completedAt',changed.completed_at,'revision',changed.revision,'updatedAt',changed.updated_at,
    'updatedBy',changed.updated_by,'days',(changed.end_date-changed.start_date)+1,
    'nights',changed.end_date-changed.start_date,'schedule',schedule);
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at)
    values(actor,p_operation_id,'conference_core_mutation',req,result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,
    entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source)
  values(actor,authz,'platform','conference',case when p_status='completed' then 'conference.lifecycle.completed' else 'conference.core.updated' end,
    'conference',p_conference_id,'platform',jsonb_build_object('name',current_row.name,'place',current_row.place,
    'startDate',current_row.start_date,'endDate',current_row.end_date,'status',current_row.status,'revision',current_row.revision),
    jsonb_build_object('name',changed.name,'place',changed.place,'startDate',changed.start_date,
    'endDate',changed.end_date,'status',changed.status,'revision',changed.revision),
    jsonb_build_object('permissionKey','conference.lifecycle.manage','authoritySource',ctx->>'authoritySource','grantId',ctx->'grantId'),
    p_operation_id,'rpc');
  return result;
end $$;

-- Final public.list_accessible_conferences.
create or replace function public.list_accessible_conferences(p_actor_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_conference public.conferences%rowtype; v_items jsonb:='[]'::jsonb;
begin
  perform public.require_current_approved_device(p_actor_device_id);
  for v_conference in select conferences.* from public.conferences conferences
    where conferences.deleted_at is null order by conferences.created_at,conferences.id loop
    begin
      perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.access.view','conference',v_conference.id::text);
      v_items:=v_items||jsonb_build_array(jsonb_build_object(
        'conferenceId',v_conference.id,'organizationId',v_conference.organization_id,
        'name',v_conference.name,'startDate',v_conference.start_date,'endDate',v_conference.end_date,
        'status',v_conference.status,'completedAt',v_conference.completed_at,'revision',v_conference.revision,
        'createdAt',v_conference.created_at,'updatedAt',v_conference.updated_at));
    exception when insufficient_privilege then null;
    end;
  end loop;
  return jsonb_build_object('conferences',v_items);
end $$;

-- Final platform_private.require_conference_transport_context.
create or replace function platform_private.require_conference_transport_context(p_device uuid,p_conference uuid,p_permission text,p_mutation boolean)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c jsonb; actor uuid; conf public.conferences%rowtype;
begin
  if p_permission not in('conference.transport.view','conference.transport.manage') then raise exception 'CONFERENCE_TRANSPORT_ARGUMENT_INVALID' using errcode='22023'; end if;
  c:=public.require_effective_module_permission(p_device,'conference',p_permission,'conference',p_conference::text); actor:=(c->>'actorUserId')::uuid;
  if platform_private.validated_phase1c_device_authorization(actor,p_device) is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  select * into conf from public.conferences where id=p_conference and deleted_at is null;
  if not found then raise exception 'CONFERENCE_NOT_FOUND' using errcode='P0002'; end if;
  if p_mutation and conf.status<>'active' then raise exception 'COMPLETED_CONFERENCE_IMMUTABLE' using errcode='55000'; end if;
  return c;
end $$;

-- Final platform_private.audit_conference_transport_assignment_removal.
create or replace function platform_private.audit_conference_transport_assignment_removal(
  p_actor uuid,p_device_authorization uuid,p_assignment public.conference_transport_assignments,
  p_operation_id uuid,p_reason text,p_permission text
) returns void language plpgsql security definer set search_path='' as $$
begin
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,
    entity_id,scope_type,old_values,new_values,metadata,operation_id,source)
  values(p_actor,p_device_authorization,'platform','conference','conference.transport.assignment_removed',
    'conference_transport_assignment',p_assignment.id,'platform',to_jsonb(p_assignment),null,
    jsonb_build_object('conferenceId',p_assignment.conference_id,'vehicleId',p_assignment.vehicle_id,
      'participationId',p_assignment.participation_id,'removalReason',p_reason,'permissionKey',p_permission),
    p_operation_id,'rpc');
end $$;

-- Final public.get_conference_transport.
create or replace function public.get_conference_transport(p_actor_device_id uuid,p_conference_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c jsonb; vehicles jsonb; assignments jsonb; can_manage boolean:=false;
begin
  c:=platform_private.require_conference_transport_context(p_actor_device_id,p_conference_id,'conference.transport.view',false);
  begin
    perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.transport.manage','conference',p_conference_id::text);
    can_manage:=true;
  exception when insufficient_privilege then null;
  end;
  select coalesce(jsonb_agg(jsonb_build_object('vehicleId',v.id,'name',v.name,'icon',v.icon,'capacity',v.capacity,'position',v.position,'revision',v.revision) order by v.position,v.id),'[]') into vehicles from public.conference_transport_vehicles v where v.conference_id=p_conference_id;
  select coalesce(jsonb_agg(jsonb_build_object('assignmentId',a.id,'vehicleId',a.vehicle_id,'participationId',a.participation_id,'mode',a.assignment_mode,'riderKind',a.rider_kind,'seatNumber',a.seat_number,'revision',a.revision,'participationStatus',p.status,'person',jsonb_build_object('personId',p.person_id,'fullName',person.full_name,'phone',person.phone),'guardianParticipationId',p.guardian_participation_id,'guardianParticipationStatus',gp.status,'guardianFullName',gperson.full_name,'roomNumber',room.room_number,'sharingEligible',a.assignment_mode<>'shared' or gp.status='active') order by a.vehicle_id,a.seat_number nulls last,a.id),'[]') into assignments
  from public.conference_transport_assignments a join public.conference_participations p on p.id=a.participation_id
  join platform.people person on person.id=p.person_id left join public.conference_participations gp on gp.id=p.guardian_participation_id
  left join platform.people gperson on gperson.id=gp.person_id left join public.conference_accommodation_occupancies o on o.participation_id=p.id
  left join public.conference_accommodation_rooms room on room.id=o.room_id where a.conference_id=p_conference_id;
  return jsonb_build_object('conferenceId',p_conference_id,'canManage',can_manage,'vehicles',vehicles,'assignments',assignments);
end $$;

-- Final public.mutate_conference_transport_vehicle.
create or replace function public.mutate_conference_transport_vehicle(p_device uuid,p_operation_id uuid,p_operation text,p_conference uuid,p_vehicle uuid,p_expected_revision bigint,p_name text,p_icon text,p_capacity integer,p_position integer,p_remove_overflow boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c jsonb; actor uuid; authz uuid; req jsonb; prior public.conference_participation_operations%rowtype;
  old public.conference_transport_vehicles%rowtype; row public.conference_transport_vehicles%rowtype;
  removed public.conference_transport_assignments%rowtype; removed_ids jsonb:='[]'::jsonb; result jsonb;
begin
  if p_operation_id is null or p_operation not in('create','update','delete') then raise exception 'CONFERENCE_TRANSPORT_ARGUMENT_INVALID' using errcode='22023'; end if;
  c:=platform_private.require_conference_transport_context(p_device,p_conference,'conference.transport.manage',true); actor:=(c->>'actorUserId')::uuid; authz:=platform_private.validated_phase1c_device_authorization(actor,p_device);
  req:=jsonb_build_object('operation',p_operation,'conferenceId',p_conference,'vehicleId',p_vehicle,'expectedRevision',p_expected_revision,'name',p_name,'icon',p_icon,'capacity',p_capacity,'position',p_position,'removeOverflow',p_remove_overflow);
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into prior from public.conference_participation_operations where actor_user_id=actor and operation_id=p_operation_id;
  if found then if prior.operation<>'transport_vehicle_'||p_operation or prior.request<>req then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023'; end if; return prior.result; end if;
  if p_operation='create' then insert into public.conference_transport_vehicles(conference_id,name,icon,capacity,position,created_by,updated_by) values(p_conference,btrim(p_name),coalesce(nullif(p_icon,''),'🚌'),p_capacity,coalesce(p_position,0),actor,actor) returning * into row;
  else select * into old from public.conference_transport_vehicles where id=p_vehicle and conference_id=p_conference for update; if not found then raise exception 'CONFERENCE_TRANSPORT_VEHICLE_NOT_FOUND' using errcode='P0002'; end if; if old.revision<>p_expected_revision then raise exception 'CONFERENCE_TRANSPORT_REVISION_CONFLICT' using errcode='40001'; end if;
    if p_operation='delete' then
      for removed in select * from public.conference_transport_assignments where vehicle_id=p_vehicle order by id for update loop
        perform platform_private.audit_conference_transport_assignment_removal(actor,authz,removed,p_operation_id,'vehicle_deleted','conference.transport.manage'); removed_ids:=removed_ids||jsonb_build_array(removed.id);
      end loop;
      delete from public.conference_transport_assignments where vehicle_id=p_vehicle; delete from public.conference_transport_vehicles where id=p_vehicle; row:=old;
    else
      if p_capacity<old.capacity and exists(select 1 from public.conference_transport_assignments where vehicle_id=p_vehicle and seat_number>p_capacity) and not coalesce(p_remove_overflow,false) then raise exception 'CONFERENCE_TRANSPORT_CAPACITY_OCCUPIED' using errcode='23514'; end if;
      if p_capacity<old.capacity then
        for removed in select * from public.conference_transport_assignments where vehicle_id=p_vehicle and seat_number>p_capacity order by id for update loop
          perform platform_private.audit_conference_transport_assignment_removal(actor,authz,removed,p_operation_id,'capacity_reduced','conference.transport.manage'); removed_ids:=removed_ids||jsonb_build_array(removed.id);
        end loop;
        delete from public.conference_transport_assignments where vehicle_id=p_vehicle and seat_number>p_capacity;
      end if;
      update public.conference_transport_vehicles set name=btrim(p_name),icon=coalesce(nullif(p_icon,''),'🚌'),capacity=p_capacity,position=coalesce(p_position,position),revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=p_vehicle returning * into row;
    end if;
  end if;
  result:=jsonb_build_object('vehicleId',row.id,'conferenceId',row.conference_id,'name',row.name,'icon',row.icon,'capacity',row.capacity,'position',row.position,'revision',row.revision,'deleted',p_operation='delete','removedAssignmentIds',removed_ids);
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at) values(actor,p_operation_id,'transport_vehicle_'||p_operation,req,result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source) values(actor,authz,'platform','conference','conference.transport.vehicle_'||p_operation,'conference_transport_vehicle',row.id,'platform',case when p_operation='create' then null else to_jsonb(old) end,case when p_operation='delete' then null else to_jsonb(row) end,jsonb_build_object('conferenceId',p_conference,'permissionKey','conference.transport.manage'),p_operation_id,'rpc'); return result;
end $$;

-- Final public.set_conference_transport_assignment.
create or replace function public.set_conference_transport_assignment(p_device uuid,p_operation_id uuid,p_conference uuid,p_participation uuid,p_vehicle uuid,p_mode text,p_rider_kind text,p_seat integer,p_expected_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c jsonb; actor uuid; authz uuid; req jsonb; prior public.conference_participation_operations%rowtype; part public.conference_participations%rowtype; guardian public.conference_participations%rowtype; vehicle public.conference_transport_vehicles%rowtype; old public.conference_transport_assignments%rowtype; row public.conference_transport_assignments%rowtype; result jsonb;
begin
  c:=platform_private.require_conference_transport_context(p_device,p_conference,'conference.transport.manage',true); actor:=(c->>'actorUserId')::uuid; authz:=platform_private.validated_phase1c_device_authorization(actor,p_device);
  req:=jsonb_build_object('conferenceId',p_conference,'participationId',p_participation,'vehicleId',p_vehicle,'mode',p_mode,'riderKind',p_rider_kind,'seatNumber',p_seat,'expectedRevision',p_expected_revision); perform pg_advisory_xact_lock(hashtextextended(actor::text||':conference-participation:'||p_operation_id::text,0)); select * into prior from public.conference_participation_operations where actor_user_id=actor and operation_id=p_operation_id; if found then if prior.operation<>'transport_assignment_set' or prior.request<>req then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023'; end if; return prior.result; end if;
  select * into part from public.conference_participations where id=p_participation and conference_id=p_conference for key share; if not found or part.status<>'active' then raise exception 'CONFERENCE_TRANSPORT_PARTICIPATION_INELIGIBLE' using errcode='23514'; end if;
  select * into vehicle from public.conference_transport_vehicles where id=p_vehicle and conference_id=p_conference for update; if not found then raise exception 'CONFERENCE_TRANSPORT_VEHICLE_NOT_FOUND' using errcode='P0002'; end if;
  if p_mode='independent' then if p_seat is null or p_seat>vehicle.capacity then raise exception 'CONFERENCE_TRANSPORT_SEAT_INVALID' using errcode='23514'; end if;
  elsif p_mode='shared' then select * into guardian from public.conference_participations where id=part.guardian_participation_id and conference_id=p_conference; if not found or guardian.status<>'active' or not exists(select 1 from public.conference_transport_assignments where participation_id=guardian.id and vehicle_id=p_vehicle and assignment_mode='independent') then raise exception 'CONFERENCE_TRANSPORT_GUARDIAN_INELIGIBLE' using errcode='23514'; end if; p_seat:=null;
  else raise exception 'CONFERENCE_TRANSPORT_MODE_INVALID' using errcode='22023'; end if;
  select * into old from public.conference_transport_assignments where conference_id=p_conference and participation_id=p_participation for update;
  if found then if p_expected_revision is null or old.revision<>p_expected_revision then raise exception 'CONFERENCE_TRANSPORT_REVISION_CONFLICT' using errcode='40001'; end if; update public.conference_transport_assignments set vehicle_id=p_vehicle,assignment_mode=p_mode,rider_kind=p_rider_kind,seat_number=p_seat,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=old.id returning * into row;
  else insert into public.conference_transport_assignments(conference_id,vehicle_id,participation_id,assignment_mode,rider_kind,seat_number,created_by,updated_by) values(p_conference,p_vehicle,p_participation,p_mode,p_rider_kind,p_seat,actor,actor) returning * into row; end if;
  if row.assignment_mode='independent' then
    update public.conference_transport_assignments child_assignment set vehicle_id=row.vehicle_id,revision=child_assignment.revision+1,updated_at=statement_timestamp(),updated_by=actor
    from public.conference_participations child where child.id=child_assignment.participation_id and child.guardian_participation_id=row.participation_id and child_assignment.assignment_mode='shared' and child_assignment.conference_id=row.conference_id and child_assignment.vehicle_id<>row.vehicle_id;
  end if;
  result:=jsonb_build_object('assignmentId',row.id,'conferenceId',row.conference_id,'vehicleId',row.vehicle_id,'participationId',row.participation_id,'mode',row.assignment_mode,'riderKind',row.rider_kind,'seatNumber',row.seat_number,'revision',row.revision); insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at) values(actor,p_operation_id,'transport_assignment_set',req,result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source) values(actor,authz,'platform','conference','conference.transport.assignment_set','conference_transport_assignment',row.id,'platform',case when old.id is null then null else to_jsonb(old) end,to_jsonb(row),jsonb_build_object('conferenceId',p_conference,'permissionKey','conference.transport.manage'),p_operation_id,'rpc'); return result;
end $$;

-- Final public.remove_conference_transport_assignment.
create or replace function public.remove_conference_transport_assignment(p_device uuid,p_operation_id uuid,p_assignment uuid,p_expected_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare old public.conference_transport_assignments%rowtype; removed public.conference_transport_assignments%rowtype;
  c jsonb; session_context jsonb; actor uuid; authz uuid; req jsonb; prior public.conference_participation_operations%rowtype;
  removed_ids jsonb:='[]'::jsonb; result jsonb;
begin
  if p_operation_id is null or p_assignment is null or p_expected_revision is null then raise exception 'CONFERENCE_TRANSPORT_ARGUMENT_INVALID' using errcode='22023'; end if;
  begin
    session_context:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;
    if session_context is null or session_context->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or (session_context->>'device_id')::uuid is distinct from p_device then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
    actor:=(session_context->>'user_id')::uuid;
  exception when invalid_text_representation or null_value_not_allowed then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end;
  authz:=platform_private.validated_phase1c_device_authorization(actor,p_device); if authz is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  req:=jsonb_build_object('assignmentId',p_assignment,'expectedRevision',p_expected_revision);
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':conference-participation:'||p_operation_id::text,0)); select * into prior from public.conference_participation_operations where actor_user_id=actor and operation_id=p_operation_id;
  if found then if prior.operation<>'transport_assignment_remove' or prior.request<>req then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023'; end if; c:=platform_private.require_conference_transport_context(p_device,(prior.result->>'conferenceId')::uuid,'conference.transport.manage',false); if (c->>'actorUserId')::uuid is distinct from actor then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if; return prior.result; end if;
  select * into old from public.conference_transport_assignments where id=p_assignment for update; if not found then raise exception 'CONFERENCE_TRANSPORT_ASSIGNMENT_NOT_FOUND' using errcode='P0002'; end if;
  c:=platform_private.require_conference_transport_context(p_device,old.conference_id,'conference.transport.manage',true); if (c->>'actorUserId')::uuid is distinct from actor then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  if old.revision<>p_expected_revision then raise exception 'CONFERENCE_TRANSPORT_REVISION_CONFLICT' using errcode='40001'; end if;
  if old.assignment_mode='independent' then
    for removed in select child_assignment.* from public.conference_transport_assignments child_assignment join public.conference_participations child on child.id=child_assignment.participation_id where child.guardian_participation_id=old.participation_id and child_assignment.assignment_mode='shared' and child_assignment.vehicle_id=old.vehicle_id order by child_assignment.id for update of child_assignment loop
      perform platform_private.audit_conference_transport_assignment_removal(actor,authz,removed,p_operation_id,'guardian_assignment_removed','conference.transport.manage'); removed_ids:=removed_ids||jsonb_build_array(removed.id);
    end loop;
    delete from public.conference_transport_assignments child_assignment using public.conference_participations child where child.id=child_assignment.participation_id and child.guardian_participation_id=old.participation_id and child_assignment.assignment_mode='shared' and child_assignment.vehicle_id=old.vehicle_id;
  end if;
  perform platform_private.audit_conference_transport_assignment_removal(actor,authz,old,p_operation_id,'assignment_removed','conference.transport.manage'); removed_ids:=removed_ids||jsonb_build_array(old.id);
  delete from public.conference_transport_assignments where id=p_assignment;
  result:=jsonb_build_object('assignmentId',p_assignment,'conferenceId',old.conference_id,'deleted',true,'removedAssignmentIds',removed_ids);
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at) values(actor,p_operation_id,'transport_assignment_remove',req,result,statement_timestamp()); return result;
end $$;

-- Final platform_private.conference_accommodation_pricing_projection.
create or replace function platform_private.conference_accommodation_pricing_projection(p_conference uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'enabled',coalesce(s.enabled,true),'pricingMode',coalesce(s.pricing_mode,'per_person_night'),
    'prices',jsonb_build_object('personNight',coalesce(s.person_night,0),'roomNight',coalesce(s.room_night,0),'personDay',coalesce(s.person_day,0),'roomDay',coalesce(s.room_day,0),'packagePrice',coalesce(s.package_price,0),'packageDayPrice',coalesce(s.package_day_price,0)),
    'roomTypePrices',jsonb_build_object('single',coalesce(s.single_price,0),'double',coalesce(s.double_price,0),'triple',coalesce(s.triple_price,0),'quadruple',coalesce(s.quadruple_price,0),'quintuple',coalesce(s.quintuple_price,0),'sextuple',coalesce(s.sextuple_price,0),'sevenPlus',coalesce(s.seven_plus_price,0)),
    'revision',coalesce(s.revision,0),'updatedAt',s.updated_at,'updatedBy',s.updated_by)
  from (select p_conference conference_id) c left join public.conference_accommodation_pricing s using(conference_id)
$$;

-- Final public.mutate_conference_accommodation_pricing.
create or replace function public.mutate_conference_accommodation_pricing(p_actor_device_id uuid,p_operation_id uuid,p_conference_id uuid,p_expected_revision bigint,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare ctx jsonb;session_ctx jsonb;actor uuid;authz uuid;prior public.conference_participation_operations%rowtype;
  current_row public.conference_accommodation_pricing%rowtype;changed public.conference_accommodation_pricing%rowtype;
  req jsonb;result jsonb;mode text;vals numeric[];action text;v_room_id uuid;room public.conference_accommodation_rooms%rowtype;excluded boolean;was_excluded boolean;
begin
  if p_operation_id is null or p_conference_id is null or jsonb_typeof(p_payload)<>'object' then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ARGUMENT_INVALID' using errcode='22023';end if;
  if p_payload ? 'action' then
    perform platform_private.require_exact_jsonb_keys(p_payload,array['action','roomId']);
    action:=p_payload->>'action';
    if action not in('EXCLUDE_ROOM','REMOVE_ROOM_EXCLUSION') then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ARGUMENT_INVALID' using errcode='22023';end if;
    begin v_room_id:=(p_payload->>'roomId')::uuid;exception when others then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ARGUMENT_INVALID' using errcode='22023';end;
  else
    perform platform_private.require_exact_jsonb_keys(p_payload,array['enabled','pricingMode','prices','roomTypePrices']);
    perform platform_private.require_exact_jsonb_keys(p_payload->'prices',array['personNight','roomNight','personDay','roomDay','packagePrice','packageDayPrice']);
    perform platform_private.require_exact_jsonb_keys(p_payload->'roomTypePrices',array['single','double','triple','quadruple','quintuple','sextuple','sevenPlus']);
    mode:=p_payload->>'pricingMode';if mode not in('per_person_night','per_room_night','per_person_day','per_room_day','fixed_package','per_day_package','room_type') then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ARGUMENT_INVALID' using errcode='22023';end if;
    begin vals:=array[(p_payload->'prices'->>'personNight')::numeric,(p_payload->'prices'->>'roomNight')::numeric,(p_payload->'prices'->>'personDay')::numeric,(p_payload->'prices'->>'roomDay')::numeric,(p_payload->'prices'->>'packagePrice')::numeric,(p_payload->'prices'->>'packageDayPrice')::numeric,(p_payload->'roomTypePrices'->>'single')::numeric,(p_payload->'roomTypePrices'->>'double')::numeric,(p_payload->'roomTypePrices'->>'triple')::numeric,(p_payload->'roomTypePrices'->>'quadruple')::numeric,(p_payload->'roomTypePrices'->>'quintuple')::numeric,(p_payload->'roomTypePrices'->>'sextuple')::numeric,(p_payload->'roomTypePrices'->>'sevenPlus')::numeric];exception when others then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ARGUMENT_INVALID' using errcode='22023';end;
    if exists(select 1 from unnest(vals) v where v<0) then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ARGUMENT_INVALID' using errcode='22023';end if;
  end if;
  session_ctx:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;actor:=(session_ctx->>'user_id')::uuid;
  if session_ctx->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or (session_ctx->>'device_id')::uuid is distinct from p_actor_device_id then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
  authz:=platform_private.validated_phase1c_device_authorization(actor,p_actor_device_id);if authz is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
  ctx:=platform_private.require_conference_accommodation_context(p_actor_device_id,p_conference_id,'conference.accommodation.manage',true);
  if (ctx->>'actorUserId')::uuid is distinct from actor then raise exception 'ACTOR_DEVICE_OVERRIDE_DENIED' using errcode='42501';end if;
  req:=jsonb_build_object('conferenceId',p_conference_id,'expectedRevision',p_expected_revision,'payload',p_payload);
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into prior from public.conference_participation_operations where actor_user_id=actor and operation_id=p_operation_id;
  if found then if prior.operation<>'accommodation_pricing_mutation' or prior.request<>req then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';end if;return prior.result;end if;
  perform pg_advisory_xact_lock(hashtextextended('conference-accommodation-pricing:'||p_conference_id::text,0));
  select * into current_row from public.conference_accommodation_pricing where conference_id=p_conference_id for update;
  if found and (p_expected_revision is null or current_row.revision<>p_expected_revision) then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_REVISION_CONFLICT' using errcode='40001';end if;
  if not found and p_expected_revision is not null and p_expected_revision<>0 then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_REVISION_CONFLICT' using errcode='40001';end if;
  if action is not null then
    select * into room from public.conference_accommodation_rooms where id=v_room_id and conference_id=p_conference_id for update;
    if not found then raise exception 'ACCOMMODATION_ROOM_NOT_FOUND' using errcode='P0002';end if;
    excluded:=exists(select 1 from public.conference_accommodation_pricing_room_exclusions where conference_id=p_conference_id and room_id=v_room_id);
    was_excluded:=excluded;
    if (action='EXCLUDE_ROOM' and excluded) or (action='REMOVE_ROOM_EXCLUSION' and not excluded) then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ROOM_INCLUSION_UNCHANGED' using errcode='55000';end if;
    if current_row.conference_id is null then
      insert into public.conference_accommodation_pricing(conference_id,created_by,updated_by) values(p_conference_id,actor,actor) returning * into changed;
    else
      update public.conference_accommodation_pricing set revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where conference_id=p_conference_id returning * into changed;
    end if;
    if action='EXCLUDE_ROOM' then
      insert into public.conference_accommodation_pricing_room_exclusions(conference_id,room_id,created_by) values(p_conference_id,v_room_id,actor);excluded:=true;
    else
      delete from public.conference_accommodation_pricing_room_exclusions where conference_id=p_conference_id and room_id=v_room_id;excluded:=false;
    end if;
    result:=jsonb_build_object('conferenceId',p_conference_id,'roomId',v_room_id,'includedInPricing',not excluded,'pricing',platform_private.conference_accommodation_pricing_projection(p_conference_id));
    insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at) values(actor,p_operation_id,'accommodation_pricing_mutation',req,result,statement_timestamp());
    insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source)
    values(actor,authz,'platform','conference',case when excluded then 'conference.accommodation.pricing_room_excluded' else 'conference.accommodation.pricing_room_included' end,'conference_accommodation_pricing_room',v_room_id,'platform',jsonb_build_object('includedInPricing',not was_excluded),jsonb_build_object('includedInPricing',not excluded),jsonb_build_object('conferenceId',p_conference_id,'permissionKey','conference.accommodation.manage','authoritySource',ctx->>'authoritySource','grantId',ctx->'grantId'),p_operation_id,'rpc');
    return result;
  end if;
  insert into public.conference_accommodation_pricing(conference_id,enabled,pricing_mode,person_night,room_night,person_day,room_day,package_price,package_day_price,single_price,double_price,triple_price,quadruple_price,quintuple_price,sextuple_price,seven_plus_price,revision,created_by,updated_by)
  values(p_conference_id,(p_payload->>'enabled')::boolean,mode,vals[1],vals[2],vals[3],vals[4],vals[5],vals[6],vals[7],vals[8],vals[9],vals[10],vals[11],vals[12],vals[13],1,actor,actor)
  on conflict(conference_id) do update set enabled=excluded.enabled,pricing_mode=excluded.pricing_mode,person_night=excluded.person_night,room_night=excluded.room_night,person_day=excluded.person_day,room_day=excluded.room_day,package_price=excluded.package_price,package_day_price=excluded.package_day_price,single_price=excluded.single_price,double_price=excluded.double_price,triple_price=excluded.triple_price,quadruple_price=excluded.quadruple_price,quintuple_price=excluded.quintuple_price,sextuple_price=excluded.sextuple_price,seven_plus_price=excluded.seven_plus_price,revision=public.conference_accommodation_pricing.revision+1,updated_at=statement_timestamp(),updated_by=actor returning * into changed;
  result:=jsonb_build_object('conferenceId',p_conference_id,'pricing',platform_private.conference_accommodation_pricing_projection(p_conference_id));
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at) values(actor,p_operation_id,'accommodation_pricing_mutation',req,result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source) values(actor,authz,'platform','conference','conference.accommodation.pricing_updated','conference_accommodation_pricing',p_conference_id,'platform',case when current_row.conference_id is null then null else to_jsonb(current_row) end,to_jsonb(changed),jsonb_build_object('conferenceId',p_conference_id,'permissionKey','conference.accommodation.manage','authoritySource',ctx->>'authoritySource','grantId',ctx->'grantId'),p_operation_id,'rpc');
  return result;
exception when invalid_text_representation or null_value_not_allowed then raise exception 'CONFERENCE_ACCOMMODATION_PRICING_ARGUMENT_INVALID' using errcode='22023';
end $$;

-- Final platform_private.require_conference_air_conditioning_context.
create or replace function platform_private.require_conference_air_conditioning_context(p_device uuid,p_conference uuid,p_permission text,p_mutation boolean) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c jsonb;actor uuid;conf public.conferences%rowtype;begin if p_permission not in('conference.air_conditioning.view','conference.air_conditioning.manage') then raise exception 'CONFERENCE_AIR_CONDITIONING_ARGUMENT_INVALID' using errcode='22023';end if;c:=public.require_effective_module_permission(p_device,'conference',p_permission,'conference',p_conference::text);actor:=(c->>'actorUserId')::uuid;if platform_private.validated_phase1c_device_authorization(actor,p_device) is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;select * into conf from public.conferences where id=p_conference and deleted_at is null;if not found then raise exception 'CONFERENCE_NOT_FOUND' using errcode='P0002';end if;if p_mutation and conf.status<>'active' then raise exception 'COMPLETED_CONFERENCE_IMMUTABLE' using errcode='55000';end if;return c;end $$;

-- Final public.get_conference_air_conditioning.
create or replace function public.get_conference_air_conditioning(p_device uuid,p_conference uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c jsonb; d jsonb; h jsonb; r jsonb;begin
 c:=platform_private.require_conference_air_conditioning_context(p_device,p_conference,'conference.air_conditioning.view',false);
 select coalesce(to_jsonb(x)-'conference_id'-'created_at'-'created_by','{}') into d from public.conference_air_conditioning_defaults x where conference_id=p_conference;
 select coalesce(jsonb_agg(to_jsonb(x)-'conference_id'-'created_at'-'created_by' order by house_id),'[]') into h from public.conference_air_conditioning_house_overrides x where conference_id=p_conference;
 select coalesce(jsonb_agg(to_jsonb(x)-'conference_id'-'created_at'-'created_by' order by room_id),'[]') into r from public.conference_air_conditioning_room_overrides x where conference_id=p_conference;
 return jsonb_build_object('conferenceId',p_conference,'defaultConfiguration',coalesce(d,jsonb_build_object('enabled',true,'pricing_basis','PER_ROOM','time_basis','DAY','duration_basis','CONFERENCE','unit_price',0,'fixed_amount',null,'include_empty_rooms',false,'include_closed_rooms',false,'units_count',null,'revision',0)),'houseOverrides',h,'roomOverrides',r);
end $$;

-- Final public.mutate_conference_air_conditioning.
create or replace function public.mutate_conference_air_conditioning(p_device uuid,p_operation_id uuid,p_conference uuid,p_scope text,p_scope_id uuid,p_action text,p_expected_revision bigint,p_configuration jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c jsonb;s jsonb;actor uuid;authz uuid;prior public.conference_participation_operations%rowtype;req jsonb;result jsonb;current_revision bigint;begin
 if p_operation_id is null or p_conference is null or p_scope not in('CONFERENCE','HOUSE','ROOM') or p_action not in('SET','CLEAR','CLEAR_SUBTREE') or (p_action='CLEAR_SUBTREE' and p_scope<>'HOUSE') or (p_scope='CONFERENCE' and p_scope_id is not null) or (p_scope<>'CONFERENCE' and p_scope_id is null) then raise exception 'CONFERENCE_AIR_CONDITIONING_ARGUMENT_INVALID' using errcode='22023';end if;
 s:=nullif(current_setting('platform.phase1c_context',true),'')::jsonb;actor:=(s->>'user_id')::uuid;if s->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or (s->>'device_id')::uuid is distinct from p_device then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
 authz:=platform_private.validated_phase1c_device_authorization(actor,p_device);if authz is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
 c:=platform_private.require_conference_air_conditioning_context(p_device,p_conference,'conference.air_conditioning.manage',true);
 req:=jsonb_build_object('conferenceId',p_conference,'scope',p_scope,'scopeId',p_scope_id,'action',p_action,'expectedRevision',p_expected_revision,'configuration',p_configuration);
 perform pg_advisory_xact_lock(hashtextextended(actor::text||':conference-participation:'||p_operation_id::text,0));select * into prior from public.conference_participation_operations where actor_user_id=actor and operation_id=p_operation_id;if found then if prior.operation<>'air_conditioning_mutation' or prior.request<>req then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';end if;return prior.result;end if;
 if p_scope='CONFERENCE' then select revision into current_revision from public.conference_air_conditioning_defaults where conference_id=p_conference for update;
 elsif p_scope='HOUSE' then perform 1 from public.conference_accommodation_houses where id=p_scope_id and conference_id=p_conference;if not found then raise exception 'CONFERENCE_ACCOMMODATION_HOUSE_NOT_FOUND' using errcode='P0002';end if;select revision into current_revision from public.conference_air_conditioning_house_overrides where house_id=p_scope_id for update;
 else perform 1 from public.conference_accommodation_rooms rr join public.conference_accommodation_floors f on f.id=rr.floor_id join public.conference_accommodation_houses h on h.id=f.house_id where rr.id=p_scope_id and h.conference_id=p_conference;if not found then raise exception 'CONFERENCE_ACCOMMODATION_ROOM_NOT_FOUND' using errcode='P0002';end if;select revision into current_revision from public.conference_air_conditioning_room_overrides where room_id=p_scope_id for update;end if;
 if current_revision is null then current_revision:=0;end if;if p_expected_revision is distinct from current_revision then raise exception 'CONFERENCE_AIR_CONDITIONING_REVISION_CONFLICT' using errcode='40001';end if;
 if p_action='CLEAR' and p_scope='CONFERENCE' then raise exception 'CONFERENCE_AIR_CONDITIONING_ARGUMENT_INVALID' using errcode='22023';end if;
 if p_action in('CLEAR','CLEAR_SUBTREE') then if p_scope='HOUSE' then if p_action='CLEAR_SUBTREE' then delete from public.conference_air_conditioning_room_overrides ro using public.conference_accommodation_rooms rr,public.conference_accommodation_floors f where ro.room_id=rr.id and rr.floor_id=f.id and f.house_id=p_scope_id;end if;delete from public.conference_air_conditioning_house_overrides where house_id=p_scope_id;else delete from public.conference_air_conditioning_room_overrides where room_id=p_scope_id;end if;
 else
  if jsonb_typeof(p_configuration)<>'object' or p_configuration ? 'manualTotal' or p_configuration ? 'dayOverrides' then raise exception 'CONFERENCE_AIR_CONDITIONING_ARGUMENT_INVALID' using errcode='22023';end if;
  if p_scope='CONFERENCE' then perform platform_private.require_exact_jsonb_keys(p_configuration,array['enabled','pricingBasis','timeBasis','durationBasis','unitPrice','fixedAmount','includeEmptyRooms','includeClosedRooms','unitsCount']);insert into public.conference_air_conditioning_defaults(conference_id,enabled,pricing_basis,time_basis,duration_basis,unit_price,fixed_amount,include_empty_rooms,include_closed_rooms,units_count,revision,created_by,updated_by) values(p_conference,(p_configuration->>'enabled')::boolean,p_configuration->>'pricingBasis',p_configuration->>'timeBasis',p_configuration->>'durationBasis',(p_configuration->>'unitPrice')::numeric,nullif(p_configuration->>'fixedAmount','')::numeric,(p_configuration->>'includeEmptyRooms')::boolean,(p_configuration->>'includeClosedRooms')::boolean,nullif(p_configuration->>'unitsCount','')::integer,1,actor,actor) on conflict(conference_id) do update set enabled=excluded.enabled,pricing_basis=excluded.pricing_basis,time_basis=excluded.time_basis,duration_basis=excluded.duration_basis,unit_price=excluded.unit_price,fixed_amount=excluded.fixed_amount,include_empty_rooms=excluded.include_empty_rooms,include_closed_rooms=excluded.include_closed_rooms,units_count=excluded.units_count,revision=public.conference_air_conditioning_defaults.revision+1,updated_at=statement_timestamp(),updated_by=actor;
  elsif p_scope='HOUSE' then perform platform_private.require_exact_jsonb_keys(p_configuration,array['enabled','pricingBasis','timeBasis','durationBasis','unitPrice','fixedAmount','includeEmptyRooms','includeClosedRooms','unitsCount']);insert into public.conference_air_conditioning_house_overrides(house_id,conference_id,enabled,pricing_basis,time_basis,duration_basis,unit_price,fixed_amount,include_empty_rooms,include_closed_rooms,units_count,revision,created_by,updated_by) values(p_scope_id,p_conference,nullif(p_configuration->>'enabled','')::boolean,nullif(p_configuration->>'pricingBasis',''),nullif(p_configuration->>'timeBasis',''),nullif(p_configuration->>'durationBasis',''),nullif(p_configuration->>'unitPrice','')::numeric,nullif(p_configuration->>'fixedAmount','')::numeric,nullif(p_configuration->>'includeEmptyRooms','')::boolean,nullif(p_configuration->>'includeClosedRooms','')::boolean,nullif(p_configuration->>'unitsCount','')::integer,1,actor,actor) on conflict(house_id) do update set enabled=excluded.enabled,pricing_basis=excluded.pricing_basis,time_basis=excluded.time_basis,duration_basis=excluded.duration_basis,unit_price=excluded.unit_price,fixed_amount=excluded.fixed_amount,include_empty_rooms=excluded.include_empty_rooms,include_closed_rooms=excluded.include_closed_rooms,units_count=excluded.units_count,revision=public.conference_air_conditioning_house_overrides.revision+1,updated_at=statement_timestamp(),updated_by=actor;
  else perform platform_private.require_exact_jsonb_keys(p_configuration,array['included','enabled','pricingBasis','timeBasis','durationBasis','unitPrice','fixedAmount','includeEmptyRooms','includeClosedRooms','unitsCount']);insert into public.conference_air_conditioning_room_overrides(room_id,conference_id,included,enabled,pricing_basis,time_basis,duration_basis,unit_price,fixed_amount,include_empty_rooms,include_closed_rooms,units_count,revision,created_by,updated_by) values(p_scope_id,p_conference,nullif(p_configuration->>'included','')::boolean,nullif(p_configuration->>'enabled','')::boolean,nullif(p_configuration->>'pricingBasis',''),nullif(p_configuration->>'timeBasis',''),nullif(p_configuration->>'durationBasis',''),nullif(p_configuration->>'unitPrice','')::numeric,nullif(p_configuration->>'fixedAmount','')::numeric,nullif(p_configuration->>'includeEmptyRooms','')::boolean,nullif(p_configuration->>'includeClosedRooms','')::boolean,nullif(p_configuration->>'unitsCount','')::integer,1,actor,actor) on conflict(room_id) do update set included=excluded.included,enabled=excluded.enabled,pricing_basis=excluded.pricing_basis,time_basis=excluded.time_basis,duration_basis=excluded.duration_basis,unit_price=excluded.unit_price,fixed_amount=excluded.fixed_amount,include_empty_rooms=excluded.include_empty_rooms,include_closed_rooms=excluded.include_closed_rooms,units_count=excluded.units_count,revision=public.conference_air_conditioning_room_overrides.revision+1,updated_at=statement_timestamp(),updated_by=actor;end if;
 end if;
 result:=public.get_conference_air_conditioning(p_device,p_conference);insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at) values(actor,p_operation_id,'air_conditioning_mutation',req,result,statement_timestamp());insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source) values(actor,authz,'platform','conference','conference.air_conditioning.configuration_changed','conference_air_conditioning_configuration',coalesce(p_scope_id,p_conference),'platform',null,p_configuration,jsonb_build_object('conferenceId',p_conference,'scope',p_scope,'permissionKey','conference.air_conditioning.manage'),p_operation_id,'rpc');return result;
end $$;

-- Final platform_private.require_conference_finance_context.
create or replace function platform_private.require_conference_finance_context(p_device uuid,p_conference uuid,p_permission text,p_mutation boolean) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c jsonb;actor uuid;conf public.conferences%rowtype;begin if p_permission not in('conference.accounts.view','conference.accounts.manage') then raise exception 'CONFERENCE_FINANCE_ARGUMENT_INVALID' using errcode='22023';end if;c:=public.require_effective_module_permission(p_device,'conference',p_permission,'conference',p_conference::text);actor:=(c->>'actorUserId')::uuid;if platform_private.validated_phase1c_device_authorization(actor,p_device) is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;select * into conf from public.conferences where id=p_conference and deleted_at is null;if not found then raise exception 'CONFERENCE_NOT_FOUND' using errcode='P0002';end if;if p_mutation and conf.status<>'active' then raise exception 'COMPLETED_CONFERENCE_IMMUTABLE' using errcode='55000';end if;return c;end $$;

-- Final platform_private.conference_finance_projection.
create or replace function platform_private.conference_finance_projection(p_conference uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s jsonb;i jsonb;a jsonb;begin
 select coalesce(to_jsonb(x)-'conference_id'-'created_at'-'created_by','{}') into s from public.conference_finance_settings x where conference_id=p_conference;
 select coalesce(jsonb_agg(to_jsonb(x)-'conference_id'-'created_at'-'created_by' order by kind,id),'[]') into i from public.conference_finance_items x where conference_id=p_conference;
 select coalesce(jsonb_agg(to_jsonb(x)-'conference_id'-'created_at'-'created_by' order by id),'[]') into a from public.conference_finance_adjustments x where conference_id=p_conference;
 return jsonb_build_object('conferenceId',p_conference,'settings',coalesce(s,jsonb_build_object('currency','EGP','rounding_precision',2,'expenses_enabled',true,'income_enabled',true,'settlements_enabled',true,'adjustments_enabled',true,'revision',0)),'items',i,'adjustments',a);
end $$;

-- Final public.get_conference_finance.
create or replace function public.get_conference_finance(p_device uuid,p_conference uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin perform platform_private.require_conference_finance_context(p_device,p_conference,'conference.accounts.view',false);return platform_private.conference_finance_projection(p_conference);end $$;

-- Final public.mutate_conference_finance.
create or replace function public.mutate_conference_finance(p_device uuid,p_operation_id uuid,p_conference uuid,p_entity text,p_action text,p_entity_id uuid,p_expected_revision bigint,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c jsonb;s jsonb;actor uuid;authz uuid;prior public.conference_participation_operations%rowtype;req jsonb;result jsonb;current_revision bigint;begin
 if p_operation_id is null or p_conference is null or p_entity not in('SETTINGS','EXPENSE','INCOME','SETTLEMENT','ADJUSTMENT') or p_action not in('UPSERT','DELETE') or (p_entity='SETTINGS' and (p_action<>'UPSERT' or p_entity_id is not null)) or (p_entity<>'SETTINGS' and p_entity_id is null) then raise exception 'CONFERENCE_FINANCE_ARGUMENT_INVALID' using errcode='22023';end if;
 s:=nullif(current_setting('platform.phase1c_context',true),'')::jsonb;actor:=(s->>'user_id')::uuid;if s->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or (s->>'device_id')::uuid is distinct from p_device then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;authz:=platform_private.validated_phase1c_device_authorization(actor,p_device);if authz is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
 c:=platform_private.require_conference_finance_context(p_device,p_conference,'conference.accounts.manage',true);req:=jsonb_build_object('conferenceId',p_conference,'entity',p_entity,'action',p_action,'entityId',p_entity_id,'expectedRevision',p_expected_revision,'payload',p_payload);
 perform pg_advisory_xact_lock(hashtextextended(actor::text||':conference-participation:'||p_operation_id::text,0));select * into prior from public.conference_participation_operations where actor_user_id=actor and operation_id=p_operation_id;if found then if prior.operation<>'finance_mutation' or prior.request<>req then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';end if;return prior.result;end if;
 if p_entity='SETTINGS' then select revision into current_revision from public.conference_finance_settings where conference_id=p_conference for update;else if p_entity='ADJUSTMENT' then select revision into current_revision from public.conference_finance_adjustments where conference_id=p_conference and id=p_entity_id for update;else select revision into current_revision from public.conference_finance_items where conference_id=p_conference and id=p_entity_id for update;end if;end if;current_revision:=coalesce(current_revision,0);if p_expected_revision is distinct from current_revision then raise exception 'CONFERENCE_FINANCE_REVISION_CONFLICT' using errcode='40001';end if;
 if p_action='DELETE' then if p_entity='ADJUSTMENT' then delete from public.conference_finance_adjustments where conference_id=p_conference and id=p_entity_id;else delete from public.conference_finance_items where conference_id=p_conference and id=p_entity_id;end if;
 elsif p_entity='SETTINGS' then perform platform_private.require_exact_jsonb_keys(p_payload,array['currency','roundingPrecision','expensesEnabled','incomeEnabled','settlementsEnabled','adjustmentsEnabled']);insert into public.conference_finance_settings(conference_id,currency,rounding_precision,expenses_enabled,income_enabled,settlements_enabled,adjustments_enabled,revision,created_by,updated_by) values(p_conference,btrim(p_payload->>'currency'),(p_payload->>'roundingPrecision')::smallint,(p_payload->>'expensesEnabled')::boolean,(p_payload->>'incomeEnabled')::boolean,(p_payload->>'settlementsEnabled')::boolean,(p_payload->>'adjustmentsEnabled')::boolean,1,actor,actor) on conflict(conference_id) do update set currency=excluded.currency,rounding_precision=excluded.rounding_precision,expenses_enabled=excluded.expenses_enabled,income_enabled=excluded.income_enabled,settlements_enabled=excluded.settlements_enabled,adjustments_enabled=excluded.adjustments_enabled,revision=public.conference_finance_settings.revision+1,updated_at=statement_timestamp(),updated_by=actor;
 elsif p_entity='ADJUSTMENT' then perform platform_private.require_exact_jsonb_keys(p_payload,array['type','category','amount','note']);insert into public.conference_finance_adjustments(id,conference_id,type,category,amount,note,revision,created_by,updated_by) values(p_entity_id,p_conference,p_payload->>'type',p_payload->>'category',(p_payload->>'amount')::numeric,coalesce(p_payload->>'note',''),1,actor,actor) on conflict(id) do update set type=excluded.type,category=excluded.category,amount=excluded.amount,note=excluded.note,revision=public.conference_finance_adjustments.revision+1,updated_at=statement_timestamp(),updated_by=actor where public.conference_finance_adjustments.conference_id=p_conference;
 else perform platform_private.require_exact_jsonb_keys(p_payload,array['name','enabled','calculationMethod','target','operation','quantity','unitPrice','amount','notes']);insert into public.conference_finance_items(id,conference_id,kind,name,enabled,calculation_method,target,operation,quantity,unit_price,amount,notes,revision,created_by,updated_by) values(p_entity_id,p_conference,p_entity,coalesce(p_payload->>'name',''),(p_payload->>'enabled')::boolean,p_payload->>'calculationMethod',nullif(p_payload->>'target',''),nullif(p_payload->>'operation',''),nullif(p_payload->>'quantity','')::numeric,nullif(p_payload->>'unitPrice','')::numeric,nullif(p_payload->>'amount','')::numeric,coalesce(p_payload->>'notes',''),1,actor,actor) on conflict(id) do update set name=excluded.name,enabled=excluded.enabled,calculation_method=excluded.calculation_method,target=excluded.target,operation=excluded.operation,quantity=excluded.quantity,unit_price=excluded.unit_price,amount=excluded.amount,notes=excluded.notes,revision=public.conference_finance_items.revision+1,updated_at=statement_timestamp(),updated_by=actor where public.conference_finance_items.conference_id=p_conference;
 end if;
 result:=platform_private.conference_finance_projection(p_conference);insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at) values(actor,p_operation_id,'finance_mutation',req,result,statement_timestamp());insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source) values(actor,authz,'platform','conference','conference.finance.changed','conference_finance',coalesce(p_entity_id,p_conference),'platform',null,p_payload,jsonb_build_object('conferenceId',p_conference,'entity',p_entity,'permissionKey','conference.accounts.manage'),p_operation_id,'rpc');return result;
end $$;

-- Final platform_private.create_conference_branding_default.
create or replace function platform_private.create_conference_branding_default()
returns trigger language plpgsql security definer set search_path='' as $$
begin insert into public.conference_branding(conference_id) values(new.id);return new;end $$;

-- Final platform_private.require_conference_branding_context.
create or replace function platform_private.require_conference_branding_context(p_device uuid,p_conference uuid,p_permission text,p_mutation boolean)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare session_ctx jsonb;ctx jsonb;actor uuid;conf public.conferences%rowtype;
begin
  if p_permission not in('conference.cards.view','conference.lifecycle.manage') then raise exception 'CONFERENCE_BRANDING_ARGUMENT_INVALID' using errcode='22023';end if;
  session_ctx:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;actor:=(session_ctx->>'user_id')::uuid;
  if session_ctx->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or (session_ctx->>'device_id')::uuid is distinct from p_device
     or platform_private.validated_phase1c_device_authorization(actor,p_device) is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
  ctx:=public.require_effective_module_permission(p_device,'conference',p_permission,'conference',p_conference::text);
  if (ctx->>'actorUserId')::uuid is distinct from actor then raise exception 'ACTOR_DEVICE_OVERRIDE_DENIED' using errcode='42501';end if;
  select * into conf from public.conferences where id=p_conference and deleted_at is null;
  if not found then raise exception 'CONFERENCE_NOT_FOUND' using errcode='P0002';end if;
  if p_mutation and conf.status<>'active' then raise exception 'COMPLETED_CONFERENCE_IMMUTABLE' using errcode='55000';end if;
  return ctx;
end $$;

-- Final platform_private.conference_branding_projection.
create or replace function platform_private.conference_branding_projection(p_conference uuid)
returns jsonb language sql stable security definer set search_path='' as $$
select jsonb_build_object('conferenceId',b.conference_id,'banner',b.banner,'serviceLogo',b.service_logo,
  'autoColors',b.auto_colors,'bannerPosition',b.banner_position,'cardTheme',b.card_theme,
  'primaryColor',b.primary_color,'secondaryColor',b.secondary_color,'textColor',b.text_color,
  'revision',b.revision,'updatedAt',b.updated_at,'updatedBy',b.updated_by)
from public.conference_branding b where b.conference_id=p_conference
$$;

create function public.get_conference_branding(p_device uuid,p_conference uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin perform platform_private.require_conference_branding_context(p_device,p_conference,'conference.cards.view',false);return platform_private.conference_branding_projection(p_conference);end $$;

-- Final public.get_conference_branding.
create or replace function public.get_conference_branding(p_device uuid,p_conference uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin perform platform_private.require_conference_branding_context(p_device,p_conference,'conference.cards.view',false);return platform_private.conference_branding_projection(p_conference);end $$;

-- Final public.mutate_conference_branding.
create or replace function public.mutate_conference_branding(p_device uuid,p_operation_id uuid,p_conference uuid,p_action text,p_expected_revision bigint,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare ctx jsonb;session_ctx jsonb;actor uuid;authz uuid;prior public.conference_participation_operations%rowtype;
  req jsonb;result jsonb;before_row public.conference_branding%rowtype;after_row public.conference_branding%rowtype;image_value text;
begin
  if p_operation_id is null or p_conference is null or p_expected_revision is null or p_expected_revision<1
     or p_action not in('SETTINGS_UPDATE','BANNER_SET','BANNER_REMOVE','SERVICE_LOGO_SET','SERVICE_LOGO_REMOVE')
     or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'CONFERENCE_BRANDING_ARGUMENT_INVALID' using errcode='22023';end if;
  session_ctx:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;actor:=(session_ctx->>'user_id')::uuid;
  if session_ctx->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or (session_ctx->>'device_id')::uuid is distinct from p_device then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
  authz:=platform_private.validated_phase1c_device_authorization(actor,p_device);if authz is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
  ctx:=platform_private.require_conference_branding_context(p_device,p_conference,'conference.lifecycle.manage',true);
  req:=jsonb_build_object('conferenceId',p_conference,'action',p_action,'expectedRevision',p_expected_revision,'payload',p_payload);
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into prior from public.conference_participation_operations where actor_user_id=actor and operation_id=p_operation_id;
  if found then if prior.operation<>'conference_branding_mutation' or prior.request<>req then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';end if;return prior.result;end if;
  select * into before_row from public.conference_branding where conference_id=p_conference for update;
  if not found then raise exception 'CONFERENCE_BRANDING_NOT_FOUND' using errcode='P0002';end if;
  if before_row.revision<>p_expected_revision then raise exception 'CONFERENCE_BRANDING_REVISION_CONFLICT' using errcode='40001';end if;
  if p_action='SETTINGS_UPDATE' then
    perform platform_private.require_exact_jsonb_keys(p_payload,array['autoColors','bannerPosition','cardTheme','primaryColor','secondaryColor','textColor']);
    update public.conference_branding set auto_colors=(p_payload->>'autoColors')::boolean,banner_position=p_payload->>'bannerPosition',card_theme=p_payload->>'cardTheme',primary_color=p_payload->>'primaryColor',secondary_color=p_payload->>'secondaryColor',text_color=p_payload->>'textColor',revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where conference_id=p_conference returning * into after_row;
  elsif p_action in('BANNER_SET','SERVICE_LOGO_SET') then
    perform platform_private.require_exact_jsonb_keys(p_payload,array['image']);image_value:=p_payload->>'image';
    if not platform_private.is_prepared_jpeg_data_url(image_value) then raise exception 'CONFERENCE_BRANDING_JPEG_DATA_URL_INVALID' using errcode='22023';end if;
    if p_action='BANNER_SET' then update public.conference_branding set banner=image_value,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where conference_id=p_conference returning * into after_row;
    else update public.conference_branding set service_logo=image_value,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where conference_id=p_conference returning * into after_row;end if;
  else
    perform platform_private.require_exact_jsonb_keys(p_payload,array[]::text[]);
    if p_action='BANNER_REMOVE' then update public.conference_branding set banner='',revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where conference_id=p_conference returning * into after_row;
    else update public.conference_branding set service_logo='',revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where conference_id=p_conference returning * into after_row;end if;
  end if;
  result:=platform_private.conference_branding_projection(p_conference);
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at) values(actor,p_operation_id,'conference_branding_mutation',req,result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source)
  values(actor,authz,'platform','conference','conference.branding.changed','conference_branding',p_conference,'platform',
    jsonb_build_object('revision',before_row.revision,'action',p_action),jsonb_build_object('revision',after_row.revision,'action',p_action),
    jsonb_build_object('conferenceId',p_conference,'permissionKey','conference.lifecycle.manage','authoritySource',ctx->>'authoritySource','grantId',ctx->'grantId'),p_operation_id,'rpc');
  return result;
end $$;

-- Final public.list_conference_activity.
create or replace function public.list_conference_activity(p_actor_device_id uuid,p_conference_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.settings.view','conference',p_conference_id::text);
  select coalesce(jsonb_agg(jsonb_build_object(
    'eventId',e.id,'action',e.action,
    'section',case when e.action like 'conference.branding.%' then 'settings' when e.action like 'conference.accommodation.%' then 'accommodation' when e.action like 'conference.output.%' then 'cards' else 'conference' end,
    'title',case e.action
      when 'conference.branding.changed' then 'تم تعديل هوية المؤتمر'
      when 'conference.output.card_shared' then 'تمت مشاركة كارت'
      when 'conference.output.card_printed' then 'تمت طباعة كارت'
      when 'conference.output.cards_printed' then 'تمت طباعة الكروت'
      else 'تم تحديث بيانات المؤتمر' end,
    'createdAt',e.occurred_at
  ) order by e.occurred_at desc),'[]'::jsonb) into result
  from (select * from platform.audit_events where module='conference'
    and metadata->>'conferenceId'=p_conference_id::text
    and action in('conference.core.updated','conference.lifecycle.completed','conference.branding.changed','conference.participation.created','conference.participation.status_changed','conference.participation.guardian_changed','conference.participation.deleted','conference.accommodation.assigned','conference.accommodation.moved','conference.accommodation.removed','conference.accommodation.pricing_updated','conference.accommodation.pricing_room_excluded','conference.accommodation.pricing_room_included','conference.transport.assignment_set','conference.transport.assignment_removed','conference.restaurant.participation_override_removed','conference.air_conditioning.configuration_changed','conference.finance.changed','conference.output.card_shared','conference.output.card_printed','conference.output.cards_printed')
    order by occurred_at desc limit 200) e;
  return jsonb_build_object('conferenceId',p_conference_id,'items',result);
end $$;

-- Final public.record_conference_output_event.
create or replace function public.record_conference_output_event(p_actor_device_id uuid,p_conference_id uuid,p_event text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare ctx jsonb;session_ctx jsonb;actor uuid;authz uuid;event_id uuid;
begin
  if p_event not in('card_shared','card_printed','cards_printed') then raise exception 'CONFERENCE_OUTPUT_EVENT_INVALID' using errcode='22023';end if;
  session_ctx:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;actor:=(session_ctx->>'user_id')::uuid;
  if session_ctx->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or (session_ctx->>'device_id')::uuid is distinct from p_actor_device_id then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
  authz:=platform_private.validated_phase1c_device_authorization(actor,p_actor_device_id);if authz is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
  ctx:=public.require_effective_module_permission(p_actor_device_id,'conference','conference.cards.export','conference',p_conference_id::text);
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,metadata,source)
  values(actor,authz,'platform','conference','conference.output.'||p_event,'conference',p_conference_id,'platform',jsonb_build_object('conferenceId',p_conference_id,'permissionKey','conference.cards.export','authoritySource',ctx->>'authoritySource','grantId',ctx->'grantId'),'rpc') returning id into event_id;
  return jsonb_build_object('recorded',true,'eventId',event_id);
end $$;

create or replace function platform_private.prevent_conference_accommodation_occupancy_reparenting()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.participation_id is distinct from old.participation_id
     or new.conference_id is distinct from old.conference_id then
    raise exception 'ACCOMMODATION_OCCUPANCY_PARENT_IMMUTABLE' using errcode='55000';
  end if;
  return new;
end $$;

create or replace function platform_private.cleanup_conference_accommodation_for_participation(
  p_participation_id uuid,p_actor_user_id uuid,p_device_authorization_id uuid,
  p_authority_context jsonb,p_cause text,p_operation_id uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_occupancy public.conference_accommodation_occupancies%rowtype;
begin
  if p_cause not in('participation_apologized','participation_deleted') then
    raise exception 'PARTICIPATION_ACCOMMODATION_CLEANUP_CAUSE_INVALID' using errcode='22023';
  end if;
  select * into v_occupancy from public.conference_accommodation_occupancies
  where participation_id=p_participation_id for update;
  if not found then return null; end if;
  delete from public.conference_accommodation_occupancies where id=v_occupancy.id;
  insert into platform.audit_events(
    actor_user_id,actor_device_authorization_id,domain,module,action,
    entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source
  ) values(
    p_actor_user_id,p_device_authorization_id,'platform','conference',
    'conference.accommodation.participation_cleanup','accommodation_occupancy',
    v_occupancy.id,'platform',to_jsonb(v_occupancy),null,
    jsonb_build_object(
      'conferenceId',v_occupancy.conference_id,'participationId',p_participation_id,
      'occupancyId',v_occupancy.id,'previousRoomId',v_occupancy.room_id,
      'cause',p_cause,'permissionKey','conference.people.manage',
      'authoritySource',p_authority_context->>'authoritySource',
      'grantId',p_authority_context->'grantId'
    ),p_operation_id,'rpc'
  );
  return v_occupancy.id;
end $$;

create or replace function platform_private.enforce_conference_participation_guardian_one_level()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_guardian public.conference_participations%rowtype;
begin
  if tg_op='UPDATE' and new.guardian_participation_id is not distinct from old.guardian_participation_id then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('conference-guardian:'||new.conference_id::text,0));
  if new.guardian_participation_id is null then return new; end if;
  if new.guardian_participation_id=new.id then
    raise exception 'CONFERENCE_GUARDIAN_SELF_REFERENCE' using errcode='23514';
  end if;
  select * into v_guardian from public.conference_participations
  where id=new.guardian_participation_id and conference_id=new.conference_id for update;
  if not found then raise exception 'CONFERENCE_GUARDIAN_SAME_CONFERENCE_REQUIRED' using errcode='23503'; end if;
  if v_guardian.guardian_participation_id is not null then
    raise exception 'CONFERENCE_GUARDIAN_ONE_LEVEL_REQUIRED' using errcode='23514';
  end if;
  perform 1 from public.conference_participations
  where conference_id=new.conference_id and guardian_participation_id=new.id for update;
  if found then raise exception 'CONFERENCE_GUARDIAN_ONE_LEVEL_REQUIRED' using errcode='23514'; end if;
  return new;
end $$;

create trigger conference_accommodation_occupancy_parent_immutable
before update of conference_id,room_id,participation_id on public.conference_accommodation_occupancies
for each row execute function platform_private.prevent_conference_accommodation_occupancy_reparenting();

create trigger conference_participation_guardian_one_level
before insert or update of guardian_participation_id on public.conference_participations
for each row execute function platform_private.enforce_conference_participation_guardian_one_level();

create trigger conferences_create_branding_default after insert on public.conferences
for each row execute function platform_private.create_conference_branding_default();

create or replace function public.create_canonical_conference(
  p_actor_device_id uuid,
  p_operation_id uuid,
  p_requested_conference_id uuid,
  p_organization_id uuid,
  p_name text,
  p_start_date date,
  p_end_date date
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_context jsonb;
  v_actor uuid;
  v_device_authorization_id uuid;
  v_name text:=btrim(coalesce(p_name,''));
  v_intent jsonb;
  v_prior public.conference_creation_operations%rowtype;
  v_permission text;
  v_grant_ids jsonb:='{}'::jsonb;
  v_grant_id uuid;
  v_result jsonb;
begin
  if p_operation_id is null or p_requested_conference_id is null
     or p_organization_id is null or v_name='' or char_length(v_name)>500
     or p_start_date is null or p_end_date is null or p_end_date<p_start_date then
    raise exception 'CANONICAL_CONFERENCE_CREATE_ARGUMENT_INVALID' using errcode='22023';
  end if;

  v_context:=public.require_effective_module_permission(
    p_actor_device_id,'conference','conference.lifecycle.create',null,null
  );
  v_actor:=(v_context->>'actorUserId')::uuid;
  v_device_authorization_id:=platform_private.validated_phase1c_device_authorization(
    v_actor,p_actor_device_id
  );
  if v_device_authorization_id is null then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end if;

  v_intent:=jsonb_build_object(
    'contract','final-canonical-conference-create-v1',
    'conferenceId',p_requested_conference_id,'organizationId',p_organization_id,
    'name',v_name,'startDate',p_start_date,'endDate',p_end_date
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_actor::text||':conference-create:'||p_operation_id::text,0)
  );
  select operations.* into v_prior
  from public.conference_creation_operations operations
  where operations.user_id=v_actor and operations.operation_id=p_operation_id;
  if found then
    if v_prior.conference_id<>p_requested_conference_id
       or v_prior.initial_metadata<>v_intent then
      raise exception 'CANONICAL_CONFERENCE_CREATE_OPERATION_MISMATCH' using errcode='22023';
    end if;
    if not exists(
      select 1 from public.conferences conference
      where conference.id=p_requested_conference_id and conference.deleted_at is null
    ) or exists(
      select 1 from (values('conference.access.view'),('conference.lifecycle.manage')) expected(permission_key)
      where not exists(
        select 1 from public.module_permission_grants grants
        where grants.user_id=v_actor and grants.module_key='conference'
          and grants.permission_key=expected.permission_key
          and grants.resource_type='conference'
          and grants.resource_id=p_requested_conference_id::text
          and grants.revoked_at is null
      )
    ) then
      raise exception 'CANONICAL_CONFERENCE_CREATE_REPLAY_STATE_INVALID' using errcode='55000';
    end if;
    return jsonb_build_object(
      'status','duplicate','operationId',p_operation_id,
      'conferenceId',p_requested_conference_id,'organizationId',p_organization_id,
      'name',v_name,'startDate',p_start_date,'endDate',p_end_date,
      'conferenceStatus','active','completedAt',null,'revision',1,'created',false
    );
  end if;

  if not exists(
    select 1 from public.organizations organization
    where organization.id=p_organization_id and organization.status='active'
  ) then
    raise exception 'ACTIVE_ORGANIZATION_REQUIRED' using errcode='23503';
  end if;
  if exists(select 1 from public.conferences where id=p_requested_conference_id) then
    raise exception 'CONFERENCE_ID_ALREADY_USED' using errcode='23505';
  end if;

  insert into public.conferences(
    id,name,owner_id,organization_id,start_date,end_date,status,
    completed_at,revision,updated_by
  ) values(
    p_requested_conference_id,v_name,v_actor,p_organization_id,
    p_start_date,p_end_date,'active',null,1,v_actor
  );

  insert into public.conference_creation_operations(
    user_id,operation_id,conference_id,initial_metadata
  ) values(v_actor,p_operation_id,p_requested_conference_id,v_intent);

  foreach v_permission in array array[
    'conference.access.view','conference.lifecycle.manage'
  ] loop
    insert into public.module_permission_grants(
      user_id,module_key,permission_key,resource_type,resource_id,
      granted_by,granted_by_device_id
    ) values(
      v_actor,'conference',v_permission,'conference',p_requested_conference_id::text,
      v_actor,p_actor_device_id
    ) returning grant_id into v_grant_id;
    v_grant_ids:=v_grant_ids||jsonb_build_object(v_permission,v_grant_id);
  end loop;

  v_result:=jsonb_build_object(
    'status','created','operationId',p_operation_id,
    'conferenceId',p_requested_conference_id,'organizationId',p_organization_id,
    'name',v_name,'startDate',p_start_date,'endDate',p_end_date,
    'conferenceStatus','active','completedAt',null,'revision',1,'created',true
  );
  insert into platform.audit_events(
    actor_user_id,actor_device_authorization_id,subject_user_id,
    domain,module,action,entity_type,entity_id,scope_type,scope_id,
    old_values,new_values,metadata,operation_id,source
  ) values(
    v_actor,v_device_authorization_id,null,
    'platform','conference','conference.lifecycle.created',
    'conference',p_requested_conference_id,'platform',null,
    null,jsonb_build_object(
      'name',v_name,'startDate',p_start_date,'endDate',p_end_date,
      'status','active','completedAt',null,'revision',1,
      'organizationId',p_organization_id
    ),jsonb_build_object(
      'permissionKey','conference.lifecycle.create',
      'authoritySource',v_context->>'authoritySource',
      'authorityGrantId',v_context->'grantId',
      'creatorResourceGrants',v_grant_ids,'deviceId',p_actor_device_id
    ),p_operation_id,'rpc'
  );
  return v_result;
end $$;

revoke all on function public.create_canonical_conference(
  uuid,uuid,uuid,uuid,text,date,date
) from public,anon,authenticated,service_role;

do $$
declare v_signature regprocedure;
begin
  for v_signature in
    select procedure.oid::regprocedure
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid=procedure.pronamespace
    where namespace.nspname in('public','platform_private')
      and procedure.proname in(
        'require_conference_participation_context','create_conference_participation',
        'create_conference_participation_with_person','list_conference_participations',
        'set_conference_participation_status','set_conference_participation_guardian',
        'delete_conference_participation','require_conference_accommodation_context',
        'prevent_conference_accommodation_occupancy_reparenting',
        'cleanup_conference_accommodation_for_participation',
        'enforce_conference_participation_guardian_one_level',
        'conference_accommodation_duration','get_conference_accommodation',
        'mutate_conference_accommodation_structure','assign_conference_accommodation',
        'move_conference_accommodation','remove_conference_accommodation',
        'get_conference_core','mutate_conference_core','list_accessible_conferences',
        'require_conference_transport_context','audit_conference_transport_assignment_removal',
        'get_conference_transport','mutate_conference_transport_vehicle',
        'set_conference_transport_assignment','remove_conference_transport_assignment',
        'require_conference_restaurant_context','get_conference_restaurant',
        'mutate_conference_restaurant','conference_accommodation_pricing_projection',
        'mutate_conference_accommodation_pricing','require_conference_air_conditioning_context',
        'get_conference_air_conditioning','mutate_conference_air_conditioning',
        'require_conference_finance_context','conference_finance_projection',
        'get_conference_finance','mutate_conference_finance',
        'is_prepared_jpeg_data_url','create_conference_branding_default',
        'require_conference_branding_context','conference_branding_projection',
        'get_conference_branding','mutate_conference_branding',
        'list_conference_activity','record_conference_output_event'
      )
  loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',v_signature);
  end loop;
end $$;

-- One deterministic owner for canonical Conference lifecycle and discovery.
-- The outer dispatcher alone establishes the verified session and supplies the
-- server-derived device. Unmatched Platform operations continue to the final
-- non-canonical core, which fails closed for unknown operations.
create or replace function platform_private.route_canonical_conference_operation(
  p_user_id uuid,p_session_id uuid,p_token_hash bytea,p_actor_device_id uuid,
  p_operation text,p_args jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if p_operation='create_canonical_conference' then
    perform platform_private.require_exact_jsonb_keys(p_args,array[
      'p_operation_id','p_requested_conference_id','p_organization_id',
      'p_name','p_start_date','p_end_date'
    ]);
    return public.create_canonical_conference(
      p_actor_device_id,(p_args->>'p_operation_id')::uuid,
      (p_args->>'p_requested_conference_id')::uuid,
      (p_args->>'p_organization_id')::uuid,p_args->>'p_name',
      (p_args->>'p_start_date')::date,(p_args->>'p_end_date')::date
    );
  elsif p_operation='mutate_conference_core' then
    perform platform_private.require_exact_jsonb_keys(p_args,array[
      'p_operation_id','p_conference_id','p_expected_revision','p_name',
      'p_place','p_start_date','p_end_date','p_status'
    ]);
    return public.mutate_conference_core(
      p_actor_device_id,(p_args->>'p_operation_id')::uuid,
      (p_args->>'p_conference_id')::uuid,
      (p_args->>'p_expected_revision')::bigint,p_args->>'p_name',
      p_args->>'p_place',(p_args->>'p_start_date')::date,
      (p_args->>'p_end_date')::date,p_args->>'p_status'
    );
  elsif p_operation='list_accessible_conferences' then
    perform platform_private.require_exact_jsonb_keys(p_args,array[]::text[]);
    return public.list_accessible_conferences(p_actor_device_id);
  elsif p_operation='get_conference_core' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_core(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='list_conference_participations' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.list_conference_participations(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='create_conference_participation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_person_id']);
    return public.create_conference_participation(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,(p_args->>'p_person_id')::uuid);
  elsif p_operation='create_conference_participation_with_person' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_full_name','p_phone','p_gender','p_date_of_birth','p_church']);
    return public.create_conference_participation_with_person(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,p_args->>'p_full_name',p_args->>'p_phone',p_args->>'p_gender',(p_args->>'p_date_of_birth')::date,p_args->>'p_church');
  elsif p_operation='set_conference_participation_status' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_participation_id','p_expected_revision','p_status']);
    return public.set_conference_participation_status(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_participation_id')::uuid,(p_args->>'p_expected_revision')::bigint,p_args->>'p_status');
  elsif p_operation='set_conference_participation_guardian' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_participation_id','p_expected_revision','p_guardian_participation_id']);
    return public.set_conference_participation_guardian(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_participation_id')::uuid,(p_args->>'p_expected_revision')::bigint,(p_args->>'p_guardian_participation_id')::uuid);
  elsif p_operation='delete_conference_participation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_participation_id','p_expected_revision']);
    return public.delete_conference_participation(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_participation_id')::uuid,(p_args->>'p_expected_revision')::bigint);
  elsif p_operation='get_conference_accommodation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_accommodation(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation in('create_accommodation_house','update_accommodation_house','delete_accommodation_house','create_accommodation_floor','update_accommodation_floor','delete_accommodation_floor','create_accommodation_room','update_accommodation_room','delete_accommodation_room') then
    return public.mutate_conference_accommodation_structure(p_actor_device_id,replace(p_operation,'_accommodation_','_'),p_args);
  elsif p_operation='assign_conference_accommodation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_room_id','p_participation_id','p_arrival_day','p_leave_day','p_bed_type','p_extra_bed_person_type']);
    return public.assign_conference_accommodation(p_actor_device_id,(p_args->>'p_conference_id')::uuid,(p_args->>'p_room_id')::uuid,(p_args->>'p_participation_id')::uuid,(p_args->>'p_arrival_day')::integer,(p_args->>'p_leave_day')::integer,p_args->>'p_bed_type',p_args->>'p_extra_bed_person_type');
  elsif p_operation='move_conference_accommodation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_occupancy_id','p_expected_revision','p_room_id','p_arrival_day','p_leave_day','p_bed_type','p_extra_bed_person_type']);
    return public.move_conference_accommodation(p_actor_device_id,(p_args->>'p_conference_id')::uuid,(p_args->>'p_occupancy_id')::uuid,(p_args->>'p_expected_revision')::bigint,(p_args->>'p_room_id')::uuid,(p_args->>'p_arrival_day')::integer,(p_args->>'p_leave_day')::integer,p_args->>'p_bed_type',p_args->>'p_extra_bed_person_type');
  elsif p_operation='remove_conference_accommodation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_occupancy_id','p_expected_revision']);
    return public.remove_conference_accommodation(p_actor_device_id,(p_args->>'p_conference_id')::uuid,(p_args->>'p_occupancy_id')::uuid,(p_args->>'p_expected_revision')::bigint);
  elsif p_operation='get_conference_transport' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_transport(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='mutate_conference_transport_vehicle' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_operation','p_conference_id','p_vehicle_id','p_expected_revision','p_name','p_icon','p_capacity','p_position','p_remove_overflow']);
    return public.mutate_conference_transport_vehicle(p_actor_device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_operation',(p_args->>'p_conference_id')::uuid,nullif(p_args->>'p_vehicle_id','')::uuid,nullif(p_args->>'p_expected_revision','')::bigint,p_args->>'p_name',p_args->>'p_icon',nullif(p_args->>'p_capacity','')::integer,nullif(p_args->>'p_position','')::integer,coalesce((p_args->>'p_remove_overflow')::boolean,false));
  elsif p_operation='set_conference_transport_assignment' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_participation_id','p_vehicle_id','p_mode','p_rider_kind','p_seat_number','p_expected_revision']);
    return public.set_conference_transport_assignment(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,(p_args->>'p_participation_id')::uuid,(p_args->>'p_vehicle_id')::uuid,p_args->>'p_mode',p_args->>'p_rider_kind',nullif(p_args->>'p_seat_number','')::integer,nullif(p_args->>'p_expected_revision','')::bigint);
  elsif p_operation='remove_conference_transport_assignment' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_assignment_id','p_expected_revision']);
    return public.remove_conference_transport_assignment(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_assignment_id')::uuid,(p_args->>'p_expected_revision')::bigint);
  elsif p_operation='get_conference_restaurant' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_restaurant(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='mutate_conference_restaurant' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_operation','p_conference_id','p_expected_revision','p_payload']);
    return public.mutate_conference_restaurant(p_actor_device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_operation',(p_args->>'p_conference_id')::uuid,nullif(p_args->>'p_expected_revision','')::bigint,p_args->'p_payload');
  elsif p_operation='mutate_conference_accommodation_pricing' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_expected_revision','p_payload']);
    return public.mutate_conference_accommodation_pricing(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,nullif(p_args->>'p_expected_revision','')::bigint,p_args->'p_payload');
  elsif p_operation='get_conference_air_conditioning' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_air_conditioning(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='mutate_conference_air_conditioning' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_scope','p_scope_id','p_action','p_expected_revision','p_configuration']);
    return public.mutate_conference_air_conditioning(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,p_args->>'p_scope',nullif(p_args->>'p_scope_id','')::uuid,p_args->>'p_action',(p_args->>'p_expected_revision')::bigint,p_args->'p_configuration');
  elsif p_operation='get_conference_finance' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_finance(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='mutate_conference_finance' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_entity','p_action','p_entity_id','p_expected_revision','p_payload']);
    return public.mutate_conference_finance(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,p_args->>'p_entity',p_args->>'p_action',nullif(p_args->>'p_entity_id','')::uuid,(p_args->>'p_expected_revision')::bigint,p_args->'p_payload');
  elsif p_operation='get_conference_branding' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_branding(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='mutate_conference_branding' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_action','p_expected_revision','p_payload']);
    return public.mutate_conference_branding(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,p_args->>'p_action',(p_args->>'p_expected_revision')::bigint,p_args->'p_payload');
  elsif p_operation='list_conference_activity' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.list_conference_activity(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='record_conference_output_event' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_event']);
    return public.record_conference_output_event(p_actor_device_id,(p_args->>'p_conference_id')::uuid,p_args->>'p_event');
  end if;
  return platform.execute_conference_device_operation_phase1c_core(
    p_user_id,p_session_id,p_token_hash,p_operation,p_args
  );
end $$;

revoke all on function platform_private.route_canonical_conference_operation(
  uuid,uuid,bytea,uuid,text,jsonb
) from public,anon,authenticated,service_role;

create or replace function platform.execute_conference_device_operation(
  p_user_id uuid,p_session_id uuid,p_token_hash bytea,p_operation text,p_args jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_session platform_private.device_sessions%rowtype;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'CONFERENCE_OPERATION_BACKEND_REQUIRED' using errcode='42501';
  end if;
  if p_user_id is null or p_session_id is null
     or pg_catalog.octet_length(p_token_hash)<>32 then
    raise exception 'DEVICE_SESSION_ARGUMENT_INVALID' using errcode='22023';
  end if;
  select session.* into v_session
  from platform_private.device_sessions session
  join platform.device_key_bindings binding on binding.id=session.binding_id
  join platform.user_device_authorizations device_authorization
    on device_authorization.id=session.device_authorization_id
  join platform.devices device on device.id=session.device_id
  join platform.profiles profile on profile.user_id=session.user_id
  where session.id=p_session_id and session.user_id=p_user_id
    and session.token_hash=p_token_hash
    and session.purpose='PLATFORM_DEVICE_SESSION'
    and session.revoked_at is null
    and session.expires_at>pg_catalog.statement_timestamp()
    and binding.user_id=session.user_id and binding.device_id=session.device_id
    and binding.device_authorization_id=session.device_authorization_id
    and binding.public_key_thumbprint=session.public_key_thumbprint
    and binding.algorithm='ECDSA_P256_SHA256'
    and binding.lifecycle_status='active'
    and binding.revoked_at is null and binding.retired_at is null
    and device_authorization.user_id=session.user_id
    and device_authorization.device_id=session.device_id
    and device_authorization.status='approved'
    and device_authorization.revoked_at is null
    and device.lifecycle_status='active' and device.retired_at is null
    and device.compromised_at is null and profile.account_status='approved';
  if not found then
    raise exception 'DEVICE_SESSION_INVALID' using errcode='42501';
  end if;
  if p_args ? 'p_actor_device_id'
     or (p_args ? 'p_device_id'
         and p_operation<>'approve_pending_device_authorization') then
    raise exception 'ACTOR_DEVICE_OVERRIDE_DENIED' using errcode='22023';
  end if;
  perform pg_catalog.set_config(
    'platform.phase1c_context',pg_catalog.jsonb_build_object(
      'purpose','PLATFORM_DEVICE_SESSION_DISPATCH','session_id',v_session.id,
      'user_id',v_session.user_id,'device_id',v_session.device_id,
      'authorization_id',v_session.device_authorization_id,
      'binding_id',v_session.binding_id,
      'token_hash',pg_catalog.encode(p_token_hash,'hex')
    )::text,true
  );
  perform pg_catalog.set_config(
    'request.jwt.claims',pg_catalog.jsonb_build_object(
      'sub',p_user_id,'role','authenticated'
    )::text,true
  );
  return platform_private.route_canonical_conference_operation(
    p_user_id,p_session_id,p_token_hash,v_session.device_id,p_operation,p_args
  );
end $$;

revoke all on function platform.execute_conference_device_operation(
  uuid,uuid,bytea,text,jsonb
) from public,anon,authenticated,service_role;
grant execute on function platform.execute_conference_device_operation(
  uuid,uuid,bytea,text,jsonb
) to service_role;

comment on function platform_private.route_canonical_conference_operation(
  uuid,uuid,bytea,uuid,text,jsonb
) is 'One final internal canonical Conference lifecycle/discovery router. The outer Platform dispatcher supplies verified server-derived actor/device context; unmatched operations fail closed through the final Platform core.';

comment on function public.create_canonical_conference(
  uuid,uuid,uuid,uuid,text,date,date
) is
'Final canonical Conference creation. The verified Platform session supplies actor/device; conference.lifecycle.create admits creation; exact conference.access.view and conference.lifecycle.manage resource grants make the created Conference discoverable and mutable without membership or role authority.';

commit;
