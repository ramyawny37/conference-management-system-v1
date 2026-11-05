begin;

alter table reservations.bookings
  add column lifecycle_status text not null default 'active'
    check (lifecycle_status in ('active','apologized')),
  add column apologized_at timestamptz,
  add column apology_reason text,
  add column apologized_by uuid references platform.profiles(user_id),
  add column apologized_by_device_id uuid references platform.devices(id),
  add constraint reservations_booking_apology_lifecycle_check check (
    (lifecycle_status='active' and apologized_at is null and apology_reason is null
      and apologized_by is null and apologized_by_device_id is null)
    or
    (lifecycle_status='apologized' and apologized_at is not null
      and nullif(btrim(apology_reason),'') is not null
      and apologized_by is not null and apologized_by_device_id is not null)
  );

create table reservations.booking_cancellation_settlements (
  id uuid primary key default extensions.gen_random_uuid(),
  scope_partition_id uuid not null,
  booking_id uuid not null unique,
  person_id uuid not null references platform.people(id) on delete restrict,
  collected_amount numeric(18,2) not null check (collected_amount>=0),
  non_refundable_amount numeric(18,2) not null default 0 check (non_refundable_amount>=0),
  refunded_amount numeric(18,2) not null default 0 check (refunded_amount>=0),
  credit_amount numeric(18,2) not null default 0 check (credit_amount>=0),
  pending_refund_amount numeric(18,2) not null default 0 check (pending_refund_amount>=0),
  reason text not null check (nullif(btrim(reason),'') is not null and char_length(reason)<=1000),
  created_at timestamptz not null default statement_timestamp(),
  created_by uuid not null references platform.profiles(user_id),
  created_by_device_id uuid not null references platform.devices(id),
  operation_id uuid not null unique references reservations.operations(operation_id) deferrable initially deferred,
  foreign key (booking_id) references reservations.bookings(id) on delete restrict,
  check (non_refundable_amount+refunded_amount+credit_amount+pending_refund_amount=collected_amount)
);

create table reservations.person_credit_accounts (
  scope_partition_id uuid not null,
  person_id uuid not null references platform.people(id) on delete restrict,
  balance numeric(18,2) not null default 0 check (balance>=0),
  revision bigint not null default 1 check (revision>0),
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  primary key (scope_partition_id,person_id)
);

create table reservations.person_credit_entries (
  id uuid primary key default extensions.gen_random_uuid(),
  scope_partition_id uuid not null,
  person_id uuid not null,
  settlement_id uuid references reservations.booking_cancellation_settlements(id) on delete restrict,
  entry_kind text not null check (entry_kind in ('issue','redeem')),
  amount numeric(18,2) not null check (amount>0),
  balance_after numeric(18,2) not null check (balance_after>=0),
  reason text not null check (nullif(btrim(reason),'') is not null and char_length(reason)<=1000),
  operation_id uuid not null unique references reservations.operations(operation_id) deferrable initially deferred,
  created_at timestamptz not null default statement_timestamp(),
  created_by uuid not null references platform.profiles(user_id),
  created_by_device_id uuid not null references platform.devices(id),
  foreign key (scope_partition_id,person_id)
    references reservations.person_credit_accounts(scope_partition_id,person_id) on delete restrict,
  check ((entry_kind='issue' and settlement_id is not null)
      or (entry_kind='redeem' and settlement_id is null))
);

create index booking_cancellation_settlements_scope_idx
  on reservations.booking_cancellation_settlements(scope_partition_id,created_at,booking_id);
create index person_credit_entries_person_idx
  on reservations.person_credit_entries(scope_partition_id,person_id,created_at,id);

alter table reservations.booking_cancellation_settlements enable row level security;
alter table reservations.booking_cancellation_settlements force row level security;
alter table reservations.person_credit_accounts enable row level security;
alter table reservations.person_credit_accounts force row level security;
alter table reservations.person_credit_entries enable row level security;
alter table reservations.person_credit_entries force row level security;
revoke all on reservations.booking_cancellation_settlements,
  reservations.person_credit_accounts,reservations.person_credit_entries
  from public,anon,authenticated,service_role;

insert into platform.permissions(
  code,domain,description,is_system,status,
  allowed_scope_mode,allowed_resource_type,sensitive_mutation
) values
 ('reservations.booking.cancel','reservations',
  'إلغاء الحجز مع الحفاظ على تاريخه التشغيلي.',true,'active','both','event',true),
 ('reservations.payment.settle','reservations',
  'تنفيذ رد أو رصيد أو تسوية مالية لحجز ملغى.',true,'active','both','event',true),
 ('reservations.credit.redeem','reservations',
  'صرف رصيد شخص مركزي مع سجل مالي غير قابل للمحو.',true,'active','both','event',true)
on conflict (code) do update set
 domain=excluded.domain,description=excluded.description,status='active',
 allowed_scope_mode='both',allowed_resource_type='event',sensitive_mutation=true,
 updated_at=statement_timestamp();

create or replace view reservations.bookings_operational
with (security_invoker=true) as
select
  booking.id,booking.booking_number,booking.participant_id,booking.event_id,
  booking.booking_type_id,booking.booking_type_name_snapshot,
  booking_type.price as price_snapshot,booking.attendance_segments_snapshot,
  booking.notes,booking.revision,booking.created_at,booking.updated_at,
  booking.created_by,booking.updated_by,booking.scope_partition_id,
  booking.lifecycle_status,booking.apologized_at,booking.apology_reason,
  booking.apologized_by,booking.apologized_by_device_id
from reservations.bookings booking
join reservations.booking_types booking_type
  on booking_type.id=booking.booking_type_id
 and booking_type.event_id=booking.event_id
 and booking_type.scope_partition_id=booking.scope_partition_id;
revoke all on reservations.bookings_operational from public,anon,authenticated,service_role;

create function reservations_private.cancel_booking_scoped(
  p_device_id uuid,p_args jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  context jsonb; replay jsonb; result jsonb; booking reservations.bookings%rowtype;
  actor uuid; operation_id uuid:=(p_args->>'p_operation_id')::uuid;
  collected numeric(18,2); non_refundable numeric(18,2); refunded numeric(18,2);
  credited numeric(18,2); pending numeric(18,2); settlement_id uuid;
  person_id uuid; credit_balance numeric(18,2); conference_id uuid;
  participation_id uuid; participation_revision bigint; conference_result jsonb;
begin
  perform platform_private.require_exact_jsonb_keys(p_args,array[
    'p_operation_id','p_booking_id','p_expected_revision','p_reason',
    'p_non_refundable_amount','p_refunded_amount','p_credit_amount','p_pending_refund_amount'
  ]);
  context:=reservations_private.resolve_booking_scope(
    p_device_id,(p_args->>'p_booking_id')::uuid,'reservations.booking.cancel'
  );
  if coalesce((p_args->>'p_non_refundable_amount')::numeric,0)>0
     or coalesce((p_args->>'p_refunded_amount')::numeric,0)>0
     or coalesce((p_args->>'p_credit_amount')::numeric,0)>0
     or coalesce((p_args->>'p_pending_refund_amount')::numeric,0)>0 then
    perform public.require_effective_module_permission(
      p_device_id,'reservations','reservations.payment.settle','event',context->>'eventId'
    );
  end if;
  replay:=reservations_private.begin_operation(operation_id,context,'cancel_booking',p_args);
  if replay is not null then return replay; end if;
  select * into booking from reservations.bookings
   where id=(context->>'bookingId')::uuid
     and event_id=(context->>'eventId')::uuid
     and scope_partition_id=(context->>'scopePartitionId')::uuid for update;
  if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002'; end if;
  if booking.revision<>(p_args->>'p_expected_revision')::bigint then
    raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001';
  end if;
  if booking.lifecycle_status<>'active' then
    raise exception 'RESERVATIONS_BOOKING_ALREADY_APOLOGIZED' using errcode='55000';
  end if;
  if nullif(btrim(p_args->>'p_reason'),'') is null then
    raise exception 'RESERVATIONS_APOLOGY_REASON_REQUIRED' using errcode='22023';
  end if;
  perform 1 from reservations.payments
   where booking_id=booking.id and scope_partition_id=booking.scope_partition_id and status='active'
   order by id for update;
  select coalesce(sum(amount),0) into collected from reservations.payments
   where booking_id=booking.id and scope_partition_id=booking.scope_partition_id and status='active';
  non_refundable:=coalesce((p_args->>'p_non_refundable_amount')::numeric,0);
  refunded:=coalesce((p_args->>'p_refunded_amount')::numeric,0);
  credited:=coalesce((p_args->>'p_credit_amount')::numeric,0);
  pending:=coalesce((p_args->>'p_pending_refund_amount')::numeric,0);
  if least(non_refundable,refunded,credited,pending)<0
     or non_refundable+refunded+credited+pending<>collected then
    raise exception 'RESERVATIONS_SETTLEMENT_ALLOCATION_INVALID' using errcode='23514';
  end if;
  select participant.person_id into person_id from reservations.participants participant
   where participant.id=booking.participant_id and participant.scope_partition_id=booking.scope_partition_id;
  actor:=(context->>'actorUserId')::uuid;

  select event.conference_id into conference_id from reservations.events event
   where event.id=booking.event_id and event.scope_partition_id=booking.scope_partition_id
     and event.scope_type='conference';
  if conference_id is not null then
    select participation.id,participation.revision into participation_id,participation_revision
      from public.conference_participations participation
     where participation.conference_id=conference_id and participation.person_id=person_id
       and participation.status='active' for update;
    if participation_id is not null then
      if exists(
        select 1 from public.conference_participations child
        join reservations.participants child_participant on child_participant.person_id=child.person_id
        join reservations.bookings child_booking on child_booking.participant_id=child_participant.id
          and child_booking.scope_partition_id=child_participant.scope_partition_id
        join reservations.payments child_payment on child_payment.booking_id=child_booking.id
          and child_payment.scope_partition_id=child_booking.scope_partition_id and child_payment.status='active'
        where child.guardian_participation_id=participation_id
          and child.status='active' and child_booking.lifecycle_status='active'
          and child_booking.id<>booking.id
      ) then raise exception 'RESERVATIONS_CHILD_BOOKING_SETTLEMENT_REQUIRED' using errcode='55000'; end if;
      conference_result:=public.set_conference_participation_status(
        p_device_id,operation_id,participation_id,participation_revision,'apologized'
      );
      update reservations.bookings child_booking set
        lifecycle_status='apologized',apologized_at=statement_timestamp(),
        apology_reason=btrim(p_args->>'p_reason'),apologized_by=actor,
        apologized_by_device_id=p_device_id,revision=revision+1,
        updated_at=statement_timestamp(),updated_by=actor
      where child_booking.id<>booking.id and child_booking.lifecycle_status='active'
        and exists(
          select 1 from reservations.participants child_participant
          join public.conference_participations changed
            on changed.person_id=child_participant.person_id and changed.conference_id=conference_id
          where child_participant.id=child_booking.participant_id
            and child_participant.scope_partition_id=child_booking.scope_partition_id
            and changed.id in (select value::uuid from jsonb_array_elements_text(conference_result->'changedParticipationIds'))
        );
    end if;
  end if;

  update reservations.bookings set lifecycle_status='apologized',
    apologized_at=statement_timestamp(),apology_reason=btrim(p_args->>'p_reason'),
    apologized_by=actor,apologized_by_device_id=p_device_id,
    revision=revision+1,updated_at=statement_timestamp(),updated_by=actor
  where id=booking.id returning revision into booking.revision;
  insert into reservations.booking_cancellation_settlements(
    scope_partition_id,booking_id,person_id,collected_amount,non_refundable_amount,
    refunded_amount,credit_amount,pending_refund_amount,reason,created_by,
    created_by_device_id,operation_id
  ) values (
    booking.scope_partition_id,booking.id,person_id,collected,non_refundable,
    refunded,credited,pending,btrim(p_args->>'p_reason'),actor,p_device_id,operation_id
  ) returning id into settlement_id;
  if credited>0 then
    insert into reservations.person_credit_accounts(scope_partition_id,person_id,balance)
      values(booking.scope_partition_id,person_id,credited)
      on conflict(scope_partition_id,person_id) do update set
        balance=reservations.person_credit_accounts.balance+excluded.balance,
        revision=reservations.person_credit_accounts.revision+1,
        updated_at=statement_timestamp()
      returning balance into credit_balance;
    insert into reservations.person_credit_entries(
      scope_partition_id,person_id,settlement_id,entry_kind,amount,balance_after,
      reason,operation_id,created_by,created_by_device_id
    ) values (booking.scope_partition_id,person_id,settlement_id,'issue',credited,
      credit_balance,btrim(p_args->>'p_reason'),operation_id,actor,p_device_id);
  end if;
  result:=jsonb_build_object(
    'bookingId',booking.id,'revision',booking.revision,'status','apologized',
    'settlementId',settlement_id,'collectedAmount',collected,
    'nonRefundableAmount',non_refundable,'refundedAmount',refunded,
    'creditAmount',credited,'pendingRefundAmount',pending
  );
  perform reservations_private.audit(context,'booking.apologized','booking',booking.id,
    operation_id,to_jsonb(booking),result);
  return reservations_private.complete_operation(operation_id,context,'cancel_booking',p_args,result);
end $$;

create function reservations_private.redeem_person_credit_scoped(
  p_device_id uuid,p_args jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare context jsonb; replay jsonb; result jsonb; account reservations.person_credit_accounts%rowtype;
 actor uuid; operation_id uuid:=(p_args->>'p_operation_id')::uuid; amount numeric(18,2);
begin
  perform platform_private.require_exact_jsonb_keys(p_args,array[
    'p_operation_id','p_event_id','p_person_id','p_expected_revision','p_amount','p_reason'
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
  actor:=(context->>'actorUserId')::uuid;
  update reservations.person_credit_accounts set balance=balance-amount,
    revision=revision+1,updated_at=statement_timestamp()
   where scope_partition_id=account.scope_partition_id and person_id=account.person_id
   returning * into account;
  insert into reservations.person_credit_entries(
    scope_partition_id,person_id,entry_kind,amount,balance_after,reason,
    operation_id,created_by,created_by_device_id
  ) values(account.scope_partition_id,account.person_id,'redeem',amount,account.balance,
    btrim(p_args->>'p_reason'),operation_id,actor,p_device_id);
  result:=jsonb_build_object('personId',account.person_id,'balance',account.balance,
    'revision',account.revision,'redeemedAmount',amount);
  perform reservations_private.audit(context,'person_credit.redeemed','person_credit',account.person_id,
    operation_id,to_jsonb(account),result);
  return reservations_private.complete_operation(operation_id,context,'redeem_person_credit',p_args,result);
end $$;

do $migration$
declare definition text; rewritten text;
begin
  definition:=pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure);
  if position('if p_operation=''update_participant_booking'' then' in definition)=0 then
    raise exception 'RESERVATIONS_CANCELLATION_MUTATION_CONTRACT_DRIFT'; end if;
  rewritten:=replace(definition,
    'if p_operation=''update_participant_booking'' then',
    'if p_operation=''cancel_booking'' then return reservations_private.cancel_booking_scoped(p_device_id,p_args); end if; if p_operation=''redeem_person_credit'' then return reservations_private.redeem_person_credit_scoped(p_device_id,p_args); end if; if p_operation=''update_participant_booking'' then');
  rewritten:=replace(rewritten,
    'select count(*) into v_count from reservations.bookings where event_id=v_event.id and scope_partition_id=v_event.scope_partition_id',
    'select count(*) into v_count from reservations.bookings where event_id=v_event.id and scope_partition_id=v_event.scope_partition_id and lifecycle_status=''active''');
  rewritten:=replace(rewritten,
    'if p_operation=''record_payment'' then',
    'if p_operation=''record_payment'' then if exists(select 1 from reservations.bookings where id=(p_args->>''p_booking_id'')::uuid and lifecycle_status<>''active'') then raise exception ''RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE'' using errcode=''55000''; end if;');
  rewritten:=replace(rewritten,
    'if p_operation=''update_attendance'' then',
    'if p_operation=''update_attendance'' then if exists(select 1 from reservations.bookings where id=(p_args->>''p_booking_id'')::uuid and lifecycle_status<>''active'') then raise exception ''RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE'' using errcode=''55000''; end if;');
  execute rewritten;

  definition:=pg_get_functiondef('reservations_private.read_scoped(uuid,text,jsonb)'::regprocedure);
  if position('if v_result is null then' in definition)=0 then
    raise exception 'RESERVATIONS_CANCELLATION_READ_CONTRACT_DRIFT'; end if;
  rewritten:=replace(definition,
    'if v_result is null then',
    $insert$if p_operation='get_booking_settlement' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_booking_id']);
      return coalesce((select to_jsonb(s)||jsonb_build_object('creditBalance',coalesce(a.balance,0),'creditRevision',coalesce(a.revision,0)) from reservations.booking_cancellation_settlements s left join reservations.person_credit_accounts a on a.scope_partition_id=s.scope_partition_id and a.person_id=s.person_id where s.booking_id=v_booking_id and s.scope_partition_id=v_partition),'null'::jsonb);
    elsif p_operation='get_cancellation_financial_summary' then
      return (select jsonb_build_object(
        'grossCollected',coalesce(sum(p.amount) filter(where p.status='active'),0),
        'actualRefunds',coalesce((select sum(s.refunded_amount) from reservations.booking_cancellation_settlements s join reservations.bookings b on b.id=s.booking_id join reservations.events e on e.id=b.event_id where s.scope_partition_id=v_partition and (v_event_id is null or e.id=v_event_id)),0),
        'netCash',coalesce(sum(p.amount) filter(where p.status='active'),0)-coalesce((select sum(s.refunded_amount) from reservations.booking_cancellation_settlements s join reservations.bookings b on b.id=s.booking_id where s.scope_partition_id=v_partition and (v_event_id is null or b.event_id=v_event_id)),0),
        'activeCollection',coalesce(sum(p.amount) filter(where p.status='active' and b.lifecycle_status='active'),0),
        'nonRefundableApologyRevenue',coalesce((select sum(s.non_refundable_amount) from reservations.booking_cancellation_settlements s join reservations.bookings b2 on b2.id=s.booking_id where s.scope_partition_id=v_partition and (v_event_id is null or b2.event_id=v_event_id)),0),
        'outstandingCredits',coalesce((select sum(a.balance) from reservations.person_credit_accounts a where a.scope_partition_id=v_partition),0),
        'pendingRefunds',coalesce((select sum(s.pending_refund_amount) from reservations.booking_cancellation_settlements s join reservations.bookings b3 on b3.id=s.booking_id where s.scope_partition_id=v_partition and (v_event_id is null or b3.event_id=v_event_id)),0)
      ) from reservations.bookings b left join reservations.payments p on p.booking_id=b.id and p.scope_partition_id=b.scope_partition_id where b.scope_partition_id=v_partition and (v_event_id is null or b.event_id=v_event_id));
    end if; if v_result is null then$insert$);
  rewritten:=replace(rewritten,
    '''bookings'',(select count(*) from reservations.bookings_operational b join reservations.events e on e.id=b.event_id and e.scope_partition_id=b.scope_partition_id where',
    '''bookings'',(select count(*) from reservations.bookings_operational b join reservations.events e on e.id=b.event_id and e.scope_partition_id=b.scope_partition_id where b.lifecycle_status=''active'' and');
  rewritten:=replace(rewritten,
    '''bookingValue'',(select coalesce(sum(b.price_snapshot),0) from reservations.bookings_operational b join reservations.events e on e.id=b.event_id and e.scope_partition_id=b.scope_partition_id where',
    '''bookingValue'',(select coalesce(sum(b.price_snapshot),0) from reservations.bookings_operational b join reservations.events e on e.id=b.event_id and e.scope_partition_id=b.scope_partition_id where b.lifecycle_status=''active'' and');
  rewritten:=replace(rewritten,
    'when p_operation in(''list_bookings'',''get_booking_detail'',''search_participants_bookings'',''get_booking_accommodation'') then ''reservations.booking.view''',
    'when p_operation in(''list_bookings'',''get_booking_detail'',''search_participants_bookings'',''get_booking_accommodation'') then ''reservations.booking.view'' when p_operation=''get_booking_settlement'' then ''reservations.payment.view'' when p_operation=''get_cancellation_financial_summary'' then ''reservations.reports.view''');
  rewritten:=replace(rewritten,
    'elsif p_operation in(''get_booking_detail'',''list_booking_payments'',''get_operational_state'',''get_booking_accommodation'') then',
    'elsif p_operation in(''get_booking_detail'',''list_booking_payments'',''get_operational_state'',''get_booking_accommodation'',''get_booking_settlement'') then');
  rewritten:=replace(rewritten,
    'or (p_operation=''get_dashboard_summary'' and p_args ? ''p_event_id'') then',
    'or (p_operation in(''get_dashboard_summary'',''get_cancellation_financial_summary'') and p_args ? ''p_event_id'') then');
  rewritten:=replace(rewritten,
    'elsif p_operation=''get_dashboard_summary'' then'||chr(10)||'  v_conference_id',
    'elsif p_operation in(''get_dashboard_summary'',''get_cancellation_financial_summary'') then'||chr(10)||'  v_conference_id');
  execute rewritten;
end $migration$;

revoke all on function reservations_private.cancel_booking_scoped(uuid,jsonb),
 reservations_private.redeem_person_credit_scoped(uuid,jsonb),
 reservations_private.mutate_scoped(uuid,text,jsonb),
 reservations_private.read_scoped(uuid,text,jsonb)
 from public,anon,authenticated,service_role;
grant execute on function reservations_private.cancel_booking_scoped(uuid,jsonb),
 reservations_private.redeem_person_credit_scoped(uuid,jsonb),
 reservations_private.mutate_scoped(uuid,text,jsonb),
 reservations_private.read_scoped(uuid,text,jsonb) to postgres;

commit;
