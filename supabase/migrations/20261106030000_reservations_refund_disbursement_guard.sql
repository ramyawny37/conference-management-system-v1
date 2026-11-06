do $$
declare source_sql text; anchor text; guard_sql text;
begin
  source_sql := pg_get_functiondef('reservations_private.cancel_booking_scoped(uuid,jsonb)'::regprocedure);
  anchor := 'if credited>0 then raise exception ''RESERVATIONS_EVENT_CREDIT_ISOLATION_REQUIRED'' using errcode=''55000''; end if;';
  guard_sql := 'if refunded>0 then raise exception ''RESERVATIONS_REFUND_DISBURSEMENT_REQUIRED'' using errcode=''55000''; end if;';
  if position(guard_sql in source_sql)>0 then return; end if;
  if position(anchor in source_sql)=0 then raise exception 'CANCELLATION_CONTRACT_DRIFT'; end if;
  execute replace(source_sql,anchor,anchor||E'\n  '||guard_sql);
end $$;