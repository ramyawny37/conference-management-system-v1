begin;

-- Inventory authority was explicitly retired earlier; remove its dormant
-- reference rows before narrowing the canonical Platform permission domains.
delete from platform.user_roles
where role_id in (select id from platform.roles where domain='inventory');
delete from platform.role_permissions
where role_id in (select id from platform.roles where domain='inventory')
   or permission_id in (select id from platform.permissions where domain='inventory');
delete from platform.roles where domain='inventory';
delete from platform.permissions where domain='inventory';

alter table platform.permissions
  drop constraint permissions_code_check,
  drop constraint permissions_domain_check,
  add constraint permissions_code_check check (
    code ~ '^(platform|conference|warehouse|reservations)\.[a-z][a-z0-9_.-]{1,110}$'
  ),
  add constraint permissions_domain_check check (
    domain in ('platform','conference','warehouse','reservations')
  );

alter table platform.permissions
  add column if not exists status text not null default 'active'
    check (status in ('active','retired')),
  add column if not exists allowed_scope_mode text not null default 'module'
    check (allowed_scope_mode in ('module','resource','both')),
  add column if not exists allowed_resource_type text null
    check (allowed_resource_type is null or allowed_resource_type ~ '^[a-z][a-z0-9_]{0,62}$'),
  add column if not exists sensitive_mutation boolean not null default false,
  add constraint permissions_scope_contract_check check (
    (allowed_scope_mode='module' and allowed_resource_type is null)
    or (allowed_scope_mode in ('resource','both') and allowed_resource_type is not null)
  );

create table platform.permission_grants (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references platform.profiles(user_id) on delete cascade,
  permission_id uuid not null references platform.permissions(id) on delete restrict,
  scope_type text not null check (scope_type in ('module','resource')),
  resource_type text null check (resource_type is null or resource_type ~ '^[a-z][a-z0-9_]{0,62}$'),
  resource_id text null check (resource_id is null or (length(resource_id) between 1 and 255 and resource_id=btrim(resource_id))),
  granted_by uuid null references platform.profiles(user_id) on delete set null,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz null,
  revoked_by uuid null references platform.profiles(user_id) on delete set null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  check (
    (scope_type='module' and resource_type is null and resource_id is null)
    or (scope_type='resource' and resource_type is not null and resource_id is not null)
  )
);

create unique index permission_grants_active_scope_idx
on platform.permission_grants(
  user_id,permission_id,scope_type,
  coalesce(resource_type,''),coalesce(resource_id,'')
) where revoked_at is null;

create index permission_grants_effective_access_idx
on platform.permission_grants(user_id,permission_id,scope_type,resource_type,resource_id,revoked_at);

alter table platform.permission_grants enable row level security;
revoke all on platform.permission_grants from public,anon,authenticated,service_role;
grant select,insert,update on platform.permission_grants to service_role;

insert into platform.permissions(
  code,domain,description,is_system,status,allowed_scope_mode,allowed_resource_type,sensitive_mutation
)
select
  catalog.permission_key,catalog.module_key,catalog.description,true,
  catalog.status,catalog.allowed_scope_mode,catalog.allowed_resource_type,catalog.sensitive_mutation
from public.module_permission_catalog catalog
where catalog.module_key in ('conference','warehouse','reservations')
on conflict(code) do update set
  domain=excluded.domain,
  description=excluded.description,
  status=excluded.status,
  allowed_scope_mode=excluded.allowed_scope_mode,
  allowed_resource_type=excluded.allowed_resource_type,
  sensitive_mutation=excluded.sensitive_mutation,
  updated_at=now();

commit;