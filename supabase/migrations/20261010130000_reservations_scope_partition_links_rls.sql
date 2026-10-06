begin;

-- Internal Reservations partition-link ledger is never a browser-facing table.
-- Keep direct privileges revoked and add RLS as defense in depth.
alter table reservations.scope_partition_links enable row level security;
revoke all on table reservations.scope_partition_links
from public, anon, authenticated, service_role;

commit;
