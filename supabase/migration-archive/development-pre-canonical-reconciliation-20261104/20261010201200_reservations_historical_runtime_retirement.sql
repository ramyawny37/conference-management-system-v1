begin;
-- Historical pre-cutover snapshots are not runtime APIs. Keeping executable
-- copies would preserve the retired Organization tenancy model.
drop function if exists reservations.mutate_pre_conference_lifecycle(uuid,text,jsonb);
drop function if exists reservations.mutate_pre_conference_scope(uuid,text,jsonb);
drop function if exists reservations.read_pre_authorization_architecture_reconciliation(uuid,text,jsonb);
drop function if exists reservations.read_pre_conference_lifecycle(uuid,text,jsonb);
drop function if exists reservations.read_pre_conference_scope(uuid,text,jsonb);
drop function if exists reservations.read_pre_report_booking_pagination(uuid,text,jsonb);
commit;
