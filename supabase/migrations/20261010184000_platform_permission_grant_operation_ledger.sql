begin;
create table platform.permission_grant_operations(
 operation_id uuid primary key,
 intent_hash text not null,
 stored_result jsonb not null,
 created_at timestamptz not null default now()
);
alter table platform.permission_grant_operations enable row level security;
revoke all on platform.permission_grant_operations from public,anon,authenticated,service_role;
grant select,insert on platform.permission_grant_operations to service_role;
commit;