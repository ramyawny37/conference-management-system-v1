begin;
alter table reservations.bookings add constraint reservations_bookings_partition_event_id_unique unique(scope_partition_id,event_id,id);
create table reservations.refund_disbursements (
 id uuid primary key default extensions.gen_random_uuid(),
 scope_partition_id uuid not null,
 event_id uuid not null,
 booking_id uuid not null,
 settlement_id uuid not null references reservations.booking_cancellation_settlements(id) on delete restrict,
 amount numeric(18,2) not null check(amount>0),
 disbursed_on date not null,
 payment_method text not null check(payment_method in ('cash','instapay','e_wallet','bank_transfer','other')),
 payment_method_other text,
 reference text,
 reason text not null check(nullif(btrim(reason),'') is not null),
 operation_id uuid not null unique references reservations.operations(operation_id) deferrable initially deferred,
 created_at timestamptz not null default statement_timestamp(),
 created_by uuid not null references platform.profiles(user_id),
 created_by_device_id uuid not null references platform.devices(id),
 constraint refund_disbursements_method_other_check check(
 (payment_method='other' and nullif(btrim(payment_method_other),'') is not null)
 or (payment_method<>'other' and payment_method_other is null)),
 constraint refund_disbursements_event_booking_fk foreign key(scope_partition_id,event_id,booking_id)
 references reservations.bookings(scope_partition_id,event_id,id) on delete restrict
);
alter table reservations.refund_disbursements enable row level security;
revoke all on reservations.refund_disbursements from public,anon,authenticated;
commit;