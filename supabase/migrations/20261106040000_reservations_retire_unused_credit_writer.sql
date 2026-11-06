do $$
declare definition text; start_marker text; end_marker text; start_at integer; end_at integer;
begin
 if exists(select 1 from reservations.person_credit_accounts limit 1)
 or exists(select 1 from reservations.person_credit_entries limit 1) then
  raise exception 'LEGACY_CREDIT_RETIREMENT_HAS_DATA';
 end if;
 definition:=pg_get_functiondef('reservations_private.cancel_booking_scoped(uuid,jsonb)'::regprocedure);
 start_marker:='  if credited>0 then'||E'\n    insert into reservations.person_credit_accounts';
 end_marker:='  result:=jsonb_build_object(';
 start_at:=position(start_marker in definition);
 end_at:=position(end_marker in definition);
 if start_at=0 then
   if position('insert into reservations.person_credit_accounts' in definition)>0 then
     raise exception 'LEGACY_CREDIT_WRITER_DRIFT';
   end if;
   return;
 end if;
 if end_at<=start_at then raise exception 'LEGACY_CREDIT_WRITER_BOUNDARY_DRIFT'; end if;
 execute left(definition,start_at-1)||substr(definition,end_at);
end $$;