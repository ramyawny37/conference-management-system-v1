begin;

do $$
declare constraint_name text;
begin
  select conname into constraint_name from pg_constraint
   where conrelid='reservations.person_credit_entries'::regclass
     and contype='c' and pg_get_constraintdef(oid) like '%settlement_id%';
  if constraint_name is null then
    raise exception 'RESERVATIONS_CREDIT_ENTRY_CONTRACT_DRIFT'; end if;
  execute format('alter table reservations.person_credit_entries drop constraint %I',constraint_name);
end $$;
alter table reservations.person_credit_entries
  add constraint person_credit_entries_source_check check (settlement_id is not null);

create or replace function reservations_private.redeem_person_credit_scoped(
  p_device_id uuid,p_args jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 context jsonb; replay jsonb; result jsonb; account reservations.person_credit_accounts%rowtype;
 settlement reservations.booking_cancellation_settlements%rowtype; actor uuid;
 operation_id uuid:=(p_args->>'p_operation_id')::uuid; amount numeric(18,2); source_balance numeric(18,2);
begin
  perform platform_private.require_exact_jsonb_keys(p_args,array[
    'p_operation_id','p_event_id','p_person_id','p_settlement_id','p_expected_revision','p_amount','p_reason'
  ]);
  context:=reservations_private.resolve_event_scope(
    p_device_id,(p_args->>'p_event_id')::uuid,'reservations.credit.redeem'
  );
  replay:=reservations_private.begin_operation(operation_id,context,'redeem_person_credit',p_args);
  if replay is not null then return replay; end if;
  amount:=(p_args->>'p_amount')::numeric;
  if amount<=0 or nullif(btrim(p_args->>'p_reason'),'') is null then
    raise exception 'RESERVATIONS_CREDIT_REDEMPTION_INVALID' using errcode='22023'; end if;
  select * into account from reservations.person_credit_accounts
   where scope_partition_id=(context->>'scopePartitionId')::uuid
     and person_id=(p_args->>'p_person_id')::uuid for update;
  if not found or account.revision<>(p_args->>'p_expected_revision')::bigint then
    raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001'; end if;
  if account.balance<amount then raise exception 'RESERVATIONS_CREDIT_BALANCE_EXCEEDED' using errcode='23514'; end if;
  select settlement_row.* into settlement from reservations.booking_cancellation_settlements settlement_row
   join reservations.bookings booking on booking.id=settlement_row.booking_id
   where settlement_row.id=(p_args->>'p_settlement_id')::uuid
     and settlement_row.person_id=account.person_id
     and settlement_row.scope_partition_id=account.scope_partition_id
     and booking.event_id=(context->>'eventId')::uuid for update of settlement_row;
  if not found then raise exception 'RESERVATIONS_CREDIT_SOURCE_NOT_FOUND' using errcode='P0002'; end if;
  select settlement.credit_amount-coalesce(sum(entry.amount) filter(where entry.entry_kind='redeem'),0)
    into source_balance from reservations.person_credit_entries entry
   where entry.settlement_id=settlement.id;
  if source_balance<amount then raise exception 'RESERVATIONS_CREDIT_SOURCE_EXCEEDED' using errcode='23514'; end if;
  actor:=(context->>'actorUserId')::uuid;
  update reservations.person_credit_accounts set balance=balance-amount,
    revision=revision+1,updated_at=statement_timestamp()
   where scope_partition_id=account.scope_partition_id and person_id=account.person_id
   returning * into account;
  insert into reservations.person_credit_entries(
    scope_partition_id,person_id,settlement_id,entry_kind,amount,balance_after,reason,
    operation_id,created_by,created_by_device_id
  ) values(account.scope_partition_id,account.person_id,settlement.id,'redeem',amount,account.balance,
    btrim(p_args->>'p_reason'),operation_id,actor,p_device_id);
  result:=jsonb_build_object('personId',account.person_id,'settlementId',settlement.id,
    'balance',account.balance,'revision',account.revision,'redeemedAmount',amount);
  perform reservations_private.audit(context,'person_credit.redeemed','person_credit',account.person_id,
    operation_id,to_jsonb(account),result);
  return reservations_private.complete_operation(operation_id,context,'redeem_person_credit',p_args,result);
end $$;

do $migration$
declare definition text; rewritten text;
begin
  definition:=pg_get_functiondef('reservations_private.read_scoped(uuid,text,jsonb)'::regprocedure);
  if position('''outstandingCredits'',coalesce((select sum(a.balance) from reservations.person_credit_accounts a where a.scope_partition_id=v_partition),0)' in definition)=0 then
    raise exception 'RESERVATIONS_CREDIT_REPORT_CONTRACT_DRIFT'; end if;
  rewritten:=replace(definition,
    '''outstandingCredits'',coalesce((select sum(a.balance) from reservations.person_credit_accounts a where a.scope_partition_id=v_partition),0)',
    '''outstandingCredits'',coalesce((select sum(s.credit_amount-coalesce(redeemed.amount,0)) from reservations.booking_cancellation_settlements s join reservations.bookings credit_booking on credit_booking.id=s.booking_id left join lateral(select sum(entry.amount) amount from reservations.person_credit_entries entry where entry.settlement_id=s.id and entry.entry_kind=''redeem'') redeemed on true where s.scope_partition_id=v_partition and (v_event_id is null or credit_booking.event_id=v_event_id)),0)');
  execute rewritten;
end $migration$;

revoke all on function reservations_private.redeem_person_credit_scoped(uuid,jsonb),
 reservations_private.read_scoped(uuid,text,jsonb)
 from public,anon,authenticated,service_role;
grant execute on function reservations_private.redeem_person_credit_scoped(uuid,jsonb),
 reservations_private.read_scoped(uuid,text,jsonb) to postgres;

commit;
