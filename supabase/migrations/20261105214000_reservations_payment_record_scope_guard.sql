-- Keep record-payment lifecycle guard behind canonical scope and permission resolution.
do $$
declare definition text; rewritten text; guard text;
begin
 definition:=pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure);
 guard:='if exists(select 1 from reservations.bookings where id=(p_args->>''p_booking_id'')::uuid and lifecycle_status<>''active'') then raise exception ''RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE'' using errcode=''55000''; end if;';
 if position('resolve_booking_scope(p_device_id,(p_args->>''p_booking_id'')::uuid,''reservations.payment.record''); '||guard in definition)>0 then return; end if;
 if position('if p_operation=''record_payment'' then '||guard in definition)=0 then raise exception 'RECORD_PAYMENT_GUARD_DRIFT'; end if;
 rewritten:=replace(definition,'if p_operation=''record_payment'' then '||guard,'if p_operation=''record_payment'' then');
 rewritten:=replace(rewritten,
 'v_context:=reservations_private.resolve_booking_scope(p_device_id,(p_args->>''p_booking_id'')::uuid,''reservations.payment.record''); v_actor:=',
 'v_context:=reservations_private.resolve_booking_scope(p_device_id,(p_args->>''p_booking_id'')::uuid,''reservations.payment.record''); '||guard||' v_actor:=');
 if rewritten=definition then raise exception 'RECORD_PAYMENT_GUARD_RELOCATION_FAILED'; end if;
 execute rewritten;
end $$;
