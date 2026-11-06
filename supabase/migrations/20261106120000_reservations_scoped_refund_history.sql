-- Extend the existing scoped reader; no parallel endpoint or writer.
do $migration$
declare fn text; old_branch text; new_branch text;
begin
 select pg_get_functiondef(p.oid) into fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='reservations_private' and p.proname='read_scoped';
 if fn is null then raise exception 'Canonical read_scoped missing'; end if;
 old_branch := 'return coalesce((select to_jsonb(s)||jsonb_build_object(''creditBalance'',coalesce(a.balance,0),''creditRevision'',coalesce(a.revision,0)) from reservations.booking_cancellation_settlements s left join reservations.bookings credit_booking on credit_booking.id=s.booking_id and credit_booking.scope_partition_id=s.scope_partition_id left join reservations.person_credit_accounts a on a.scope_partition_id=s.scope_partition_id and a.event_id=credit_booking.event_id and a.person_id=s.person_id where s.booking_id=v_booking_id and s.scope_partition_id=v_partition),''null''::jsonb);';
 new_branch := 'return coalesce((select to_jsonb(s)||jsonb_build_object(''refundDisbursements'',coalesce((select jsonb_agg(jsonb_build_object(''id'',d.id,''amount'',d.amount,''disbursedOn'',d.disbursed_on,''paymentMethod'',d.payment_method,''paymentMethodOther'',d.payment_method_other,''reference'',d.reference,''reason'',d.reason,''createdAt'',d.created_at) order by d.disbursed_on,d.created_at,d.id) from reservations.refund_disbursements d where d.booking_id=s.booking_id and d.scope_partition_id=s.scope_partition_id and d.event_id=b.event_id),''[]''::jsonb)) from reservations.booking_cancellation_settlements s join reservations.bookings b on b.id=s.booking_id and b.scope_partition_id=s.scope_partition_id where s.booking_id=v_booking_id and s.scope_partition_id=v_partition),''null''::jsonb);';
 if position(old_branch in fn)=0 then raise exception 'Canonical settlement reader contract changed'; end if;
 fn:=replace(fn,old_branch,new_branch);
 execute fn;
end $migration$;
