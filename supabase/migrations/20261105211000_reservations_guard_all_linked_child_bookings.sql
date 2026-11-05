-- Do not implicitly apologize a child's unpaid booking without a settlement.
-- Every active linked child booking must be settled before guardian cancellation.
-- Keep the existing family lifecycle and single canonical writer.
do $$
declare source_sql text; updated_sql text;
begin
 source_sql:=pg_get_functiondef('reservations_private.cancel_booking_scoped(uuid,jsonb)'::regprocedure);
 if position('join reservations.payments child_payment' in source_sql)=0 then return; end if;
 updated_sql:=replace(source_sql,
 'join reservations.payments child_payment on child_payment.booking_id=child_booking.id'||chr(10)||'          and child_payment.scope_partition_id=child_booking.scope_partition_id and child_payment.status=''active''',
 '');
 if updated_sql=source_sql then raise exception 'CHILD_SETTLEMENT_GUARD_DRIFT'; end if;
 execute updated_sql;
end $$;
