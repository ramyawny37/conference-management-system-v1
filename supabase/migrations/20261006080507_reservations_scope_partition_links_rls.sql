begin;
alter table reservations.scope_partition_links enable row level security;
revoke all on table reservations.scope_partition_links
from public, anon, authenticated, service_role;
commit;;
