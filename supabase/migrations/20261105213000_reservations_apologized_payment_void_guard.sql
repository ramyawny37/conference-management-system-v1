-- Preserve immutable payment history after a booking is apologized.
-- Authorization/scope resolution stays ahead of the lifecycle guard.
do $$
declare definition text; rewritten text; guard text;
begin
 definition:=pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure);
 guard:='if exists(select 1 from reservations.payments guard_payment join reservations.bookings guard_booking on guard_booking.id=guard_payment.booking_id and guard_booking.scope_partition_id=guard_payment.scope_partition_id where guard_payment.id=(p_args->>''p_payment_id'')::uuid and guard_booking.lifecycle_status<>''active'') then raise exception ''RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE'' using errcode=''55000''; end if;';
 if position('resolve_payment_scope(p_device_id,(p_args->>''p_payment_id'')::uuid,''reservations.payment.void''); '||guard in definition)>0 then return; end if;
 if position('if p_operation=''void_payment'' then' in definition)=0 then raise exception 'VOID_PAYMENT_BRANCH_DRIFT'; end if;
 rewritten:=replace(definition,
 'v_context:=reservations_private.resolve_payment_scope(p_device_id,(p_args->>''p_payment_id'')::uuid,''reservations.payment.void''); v_actor:=',
 'v_context:=reservations_private.resolve_payment_scope(p_device_id,(p_args->>''p_payment_id'')::uuid,''reservations.payment.void''); '||guard||' v_actor:=');
 if rewritten=definition then raise exception 'VOID_PAYMENT_GUARD_INSERTION_FAILED'; end if;
 execute rewritten;
end $$;
