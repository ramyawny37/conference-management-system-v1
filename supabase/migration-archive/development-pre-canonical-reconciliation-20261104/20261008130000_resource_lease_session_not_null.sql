begin;
alter table platform.resource_leases alter column holder_session_id set not null;
commit;