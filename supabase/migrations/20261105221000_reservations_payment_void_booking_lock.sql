-- Serialize voiding a payment against booking cancellation using the same booking lock.
do $$
declare definition text; patched text; old_guard text; payment_anchor text; new_guard text;
begin
 definition:=pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure);
 old_guard:='if exists(select 1 from reservations.payments guard_payment join reservations.bookings guard_booking on guard_booking.id=guard_payment.booking_id and guard_booking.scope_partition_id=guard_payment.scope_partition_id where guard_payment.id=(p_args->>''p_payment_id'')::uuid and guard_booking.lifecycle_status<>''active'') then raise exception ''RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE'' using errcode=''55000''; end if; ';
 payment_anchor:='select * into v_payment from reservations.payments where id=(v_context->>''paymentId'')::uuid';
 new_guard:='select * into v_booking from reservations.bookings where id=(v_context->>''bookingId'')::uuid and scope_partition_id=(v_context->>''scopePartitionId'')::uuid for update; if not found then raise exception ''RESERVATIONS_BOOKING_NOT_FOUND'' using errcode=''P0002''; end if; if v_booking.lifecycle_status<>''active'' then raise exception ''RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE'' using errcode=''55000''; end if; ';
 if position(new_guard||payment_anchor in definition)>0 then return; end if;
 if position(old_guard in definition)=0 or position(payment_anchor in definition)=0 then raise exception 'VOID_PAYMENT_LOCK_CONTRACT_DRIFT'; end if;
 patched:=replace(definition,old_guard,'');
 patched:=replace(patched,payment_anchor,new_guard||payment_anchor);
 if patched=definition then raise exception 'VOID_PAYMENT_LOCK_NOT_INSTALLED'; end if;
 execute patched;
end $$;
