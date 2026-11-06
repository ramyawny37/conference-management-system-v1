begin;
do $$
begin
 if exists(select 1 from reservations.person_credit_accounts limit 1)
 or exists(select 1 from reservations.person_credit_entries limit 1) then
 raise exception 'EVENT_CREDIT_MIGRATION_REQUIRES_RECONCILIATION';
 end if;
end $$;
alter table reservations.person_credit_accounts add column event_id uuid;
alter table reservations.person_credit_entries add column event_id uuid;
alter table reservations.person_credit_accounts alter column event_id set not null;
alter table reservations.person_credit_entries alter column event_id set not null;
alter table reservations.person_credit_entries drop constraint person_credit_entries_scope_partition_id_person_id_fkey;
alter table reservations.person_credit_accounts drop constraint person_credit_accounts_pkey;
alter table reservations.person_credit_accounts add constraint person_credit_accounts_pkey primary key(scope_partition_id,event_id,person_id);
alter table reservations.person_credit_accounts add constraint person_credit_accounts_event_fk foreign key(scope_partition_id,event_id) references reservations.events(scope_partition_id,id) on delete restrict;
alter table reservations.person_credit_entries add constraint person_credit_entries_event_account_fk foreign key(scope_partition_id,event_id,person_id) references reservations.person_credit_accounts(scope_partition_id,event_id,person_id) on delete restrict;
alter table reservations.person_credit_entries add constraint person_credit_entries_event_fk foreign key(scope_partition_id,event_id) references reservations.events(scope_partition_id,id) on delete restrict;
commit;