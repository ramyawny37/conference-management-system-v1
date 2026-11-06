do $$
declare original text; old_join text; new_join text;
begin
 original:=pg_get_functiondef('reservations_private.read_scoped(uuid,text,jsonb)'::regprocedure);
 old_join:='left join reservations.person_credit_accounts a on a.scope_partition_id=s.scope_partition_id and a.person_id=s.person_id where s.booking_id=v_booking_id';
 new_join:='left join reservations.bookings credit_booking on credit_booking.id=s.booking_id and credit_booking.scope_partition_id=s.scope_partition_id left join reservations.person_credit_accounts a on a.scope_partition_id=s.scope_partition_id and a.event_id=credit_booking.event_id and a.person_id=s.person_id where s.booking_id=v_booking_id';
 if position(new_join in original)>0 then return; end if;
 if position(old_join in original)=0 then raise exception 'BOOKING_SETTLEMENT_EVENT_JOIN_DRIFT'; end if;
 execute replace(original,old_join,new_join);
end $$;