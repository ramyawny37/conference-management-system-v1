create or replace function reservations_private.disburse_refund_scoped(p_device_id uuid,p_args jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare
 ctx jsonb; replay jsonb; result jsonb; booking reservations.bookings%rowtype;
 settlement reservations.booking_cancellation_settlements%rowtype;
 op_id uuid:=(p_args->>'p_operation_id')::uuid;
 amount numeric(18,2); actor uuid; refund_id uuid;
begin
 perform platform_private.require_exact_jsonb_keys(p_args,array[
 'p_operation_id','p_booking_id','p_amount','p_disbursed_on','p_payment_method',
 'p_payment_method_other','p_reference','p_reason']);
 ctx:=reservations_private.resolve_booking_scope(p_device_id,(p_args->>'p_booking_id')::uuid,'reservations.payment.settle');
 replay:=reservations_private.begin_operation(op_id,ctx,'disburse_refund',p_args);
 if replay is not null then return replay; end if;
 select * into booking from reservations.bookings where id=(ctx->>'bookingId')::uuid
 and event_id=(ctx->>'eventId')::uuid and scope_partition_id=(ctx->>'scopePartitionId')::uuid for update;
 if not found or booking.lifecycle_status<>'apologized' then
 raise exception 'RESERVATIONS_REFUND_BOOKING_NOT_APOLOGIZED' using errcode='55000'; end if;
 select * into settlement from reservations.booking_cancellation_settlements
 where booking_id=booking.id and scope_partition_id=booking.scope_partition_id for update;
 if not found then raise exception 'RESERVATIONS_REFUND_SETTLEMENT_MISSING' using errcode='P0002'; end if;
 amount:=(p_args->>'p_amount')::numeric(18,2);
 if amount is null or amount<=0 or amount>settlement.pending_refund_amount then
 raise exception 'RESERVATIONS_REFUND_AMOUNT_EXCEEDS_DUE' using errcode='23514'; end if;
 if (p_args->>'p_disbursed_on')::date is null
 or (p_args->>'p_disbursed_on')::date>current_date then
 raise exception 'RESERVATIONS_REFUND_DATE_INVALID' using errcode='22023'; end if;
 actor:=(ctx->>'actorUserId')::uuid;
 insert into reservations.refund_disbursements(
 scope_partition_id,event_id,booking_id,settlement_id,amount,disbursed_on,
 payment_method,payment_method_other,reference,reason,operation_id,created_by,created_by_device_id)
 values(booking.scope_partition_id,booking.event_id,booking.id,settlement.id,amount,
 (p_args->>'p_disbursed_on')::date,p_args->>'p_payment_method',
 nullif(btrim(p_args->>'p_payment_method_other'),''),nullif(btrim(p_args->>'p_reference'),''),
 btrim(p_args->>'p_reason'),op_id,actor,p_device_id) returning id into refund_id;
 update reservations.booking_cancellation_settlements set
 refunded_amount=refunded_amount+amount,pending_refund_amount=pending_refund_amount-amount
 where id=settlement.id;
 result:=jsonb_build_object('refundId',refund_id,'bookingId',booking.id,'eventId',booking.event_id,
 'amount',amount,'disbursedOn',(p_args->>'p_disbursed_on')::date);
 perform reservations_private.audit(ctx,'booking.refund.disbursed','booking',booking.id,op_id,to_jsonb(settlement),result);
 return reservations_private.complete_operation(op_id,ctx,'disburse_refund',p_args,result);
end $$;
revoke all on function reservations_private.disburse_refund_scoped(uuid,jsonb) from public,anon,authenticated;