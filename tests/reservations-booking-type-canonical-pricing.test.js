'use strict';

const assert=require('node:assert/strict');
const {execFileSync}=require('node:child_process');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const test=require('node:test');

const root=path.join(__dirname,'..');
const migration=path.join(root,'supabase/migrations/20261104181547_reservations_booking_type_canonical_pricing.sql');
const sql=fs.readFileSync(migration,'utf8');
const runtime=fs.readFileSync(path.join(root,'modules/reservations/reservations-module.js'),'utf8');

test('canonical pricing rewrites the existing readers without adding a writer or snapshot synchronization',()=>{
  assert.match(sql,/booking_type\.price as price_snapshot/);
  assert.match(sql,/booking_type\.event_id=booking\.event_id/);
  assert.match(sql,/booking_type\.scope_partition_id=booking\.scope_partition_id/);
  assert.match(sql,/reservations\.bookings_operational b/);
  assert.match(sql,/reservations\.bookings_operational booking/);
  assert.doesNotMatch(sql,/update reservations\.bookings[\s\S]*price_snapshot|create trigger|legacy|fallback/i);
  assert.match(sql,/security_invoker=true/);
  assert.match(sql,/revoke all on reservations\.bookings_operational[\s\S]*public,anon,authenticated,service_role/);
  const eventEditor=runtime.slice(runtime.indexOf('function DN('),runtime.indexOf('function DN(')+9000);
  assert.match(eventEditor,/await Me\.saveBookingType\(O\)[\s\S]*await I\(\)[\s\S]*await refreshBookingContext\(\)/);
  assert.match(runtime,/priceSnapshot:ut\(t,"price_snapshot"\)/);
});

const postgresApp='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=fs.existsSync(path.join(postgresApp,'psql'))?postgresApp:'';
const database=`reservations_canonical_price_${process.pid}_${Date.now()}`;
const connection=['-h',process.env.PGHOST||'/tmp','-p',process.env.PGPORT||'5432','-U',process.env.PGUSER||os.userInfo().username];
function command(name,args,options={}){
  return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe',...options}).trim();
}
function query(statement){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement]);}

test('price changes immediately recalculate old and new bookings while preserving payments and event isolation',()=>{
  command('createdb',[database]);
  try{
    query(`
      create extension if not exists pgcrypto;
      do $$begin
        if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if;
        if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
        if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
      end$$;
      create schema reservations;
      create schema reservations_private;
      create table reservations.booking_types(
        id uuid primary key,event_id uuid not null,scope_partition_id uuid not null,
        price numeric(18,2) not null
      );
      create table reservations.bookings(
        id uuid primary key,booking_number text not null,participant_id uuid not null,
        event_id uuid not null,booking_type_id uuid not null,
        booking_type_name_snapshot text not null,price_snapshot numeric(18,2) not null,
        attendance_segments_snapshot text[] not null default '{}',notes text,
        revision bigint not null default 1,created_at timestamptz not null default now(),
        updated_at timestamptz not null default now(),created_by uuid not null,
        updated_by uuid not null,scope_partition_id uuid not null
      );
      create table reservations.payments(
        id uuid primary key,booking_id uuid not null,scope_partition_id uuid not null,
        amount numeric(18,2) not null,payment_date date not null,status text not null
      );
      create function reservations_private.read_scoped(p_device_id uuid,p_operation text,p_args jsonb) returns jsonb
      language plpgsql stable security definer set search_path='' as $$
      declare result jsonb;
      begin
        select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.booking_number),'[]') into result
        from (
          select b.booking_number,b.price_snapshot,coalesce(p.total_paid,0) total_paid,
            greatest(b.price_snapshot-coalesce(p.total_paid,0),0) remaining_balance,
            greatest(coalesce(p.total_paid,0)-b.price_snapshot,0) overpaid_amount,
            case when coalesce(p.total_paid,0)=0 then 'unpaid'
              when p.total_paid>=b.price_snapshot then 'paid' else 'partial' end payment_status
          from reservations.bookings b
          left join lateral(
            select sum(payment.amount) total_paid from reservations.payments payment
            where payment.booking_id=b.id and payment.scope_partition_id=b.scope_partition_id
              and payment.status='active'
          ) p on true
          where b.event_id=(p_args->>'eventId')::uuid
          order by b.booking_number
        ) row_data;
        return result;
      end $$;
      create function public.list_conference_participations(uuid,uuid) returns jsonb
      language sql stable security definer set search_path='' as $$
        select coalesce(jsonb_agg(jsonb_build_object(
          'bookingNumber',booking.booking_number,'priceSnapshot',booking.price_snapshot
        ) order by booking.booking_number),'[]')
        from reservations.bookings booking
        where booking.event_id=$2
      $$;
      insert into reservations.booking_types values
        ('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',750),
        ('10000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',900),
        ('10000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000002',600);
      insert into reservations.bookings(
        id,booking_number,participant_id,event_id,booking_type_id,
        booking_type_name_snapshot,price_snapshot,created_by,updated_by,scope_partition_id
      ) values
        ('40000000-0000-4000-8000-000000000001','NONE','50000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','A',750,gen_random_uuid(),gen_random_uuid(),'30000000-0000-4000-8000-000000000001'),
        ('40000000-0000-4000-8000-000000000002','PARTIAL','50000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','A',750,gen_random_uuid(),gen_random_uuid(),'30000000-0000-4000-8000-000000000001'),
        ('40000000-0000-4000-8000-000000000003','FULL','50000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','A',750,gen_random_uuid(),gen_random_uuid(),'30000000-0000-4000-8000-000000000001'),
        ('40000000-0000-4000-8000-000000000004','OTHER-TYPE','50000000-0000-4000-8000-000000000004','20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','B',900,gen_random_uuid(),gen_random_uuid(),'30000000-0000-4000-8000-000000000001'),
        ('40000000-0000-4000-8000-000000000005','OTHER-EVENT','50000000-0000-4000-8000-000000000005','20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000003','C',600,gen_random_uuid(),gen_random_uuid(),'30000000-0000-4000-8000-000000000002');
      insert into reservations.payments values
        ('60000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000001',200,'2026-11-01','active'),
        ('60000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000003','30000000-0000-4000-8000-000000000001',750,'2026-11-02','active');
    `);
    const paymentState=query("select md5(string_agg(row_to_json(payment)::text,'|' order by payment.id)) from reservations.payments payment");
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',migration]);

    query("update reservations.booking_types set price=700 where id='10000000-0000-4000-8000-000000000001'");
    const first=JSON.parse(query("select reservations_private.read_scoped(gen_random_uuid(),'list',jsonb_build_object('eventId','20000000-0000-4000-8000-000000000001'))"));
    const byNumber=Object.fromEntries(first.map(row=>[row.booking_number,row]));
    assert.deepEqual(byNumber.NONE,{booking_number:'NONE',price_snapshot:700,total_paid:0,remaining_balance:700,overpaid_amount:0,payment_status:'unpaid'});
    assert.deepEqual(byNumber.PARTIAL,{booking_number:'PARTIAL',price_snapshot:700,total_paid:200,remaining_balance:500,overpaid_amount:0,payment_status:'partial'});
    assert.deepEqual(byNumber.FULL,{booking_number:'FULL',price_snapshot:700,total_paid:750,remaining_balance:0,overpaid_amount:50,payment_status:'paid'});
    assert.equal(byNumber['OTHER-TYPE'].price_snapshot,900);
    assert.equal(query("select price_snapshot from reservations.bookings where booking_number='FULL'"),'750.00');
    assert.equal(query("select md5(string_agg(row_to_json(payment)::text,'|' order by payment.id)) from reservations.payments payment"),paymentState);

    query(`insert into reservations.bookings(
      id,booking_number,participant_id,event_id,booking_type_id,
      booking_type_name_snapshot,price_snapshot,created_by,updated_by,scope_partition_id
    ) values(
      '40000000-0000-4000-8000-000000000006','NEW','50000000-0000-4000-8000-000000000006',
      '20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',
      'A',700,gen_random_uuid(),gen_random_uuid(),'30000000-0000-4000-8000-000000000001'
    )`);
    query("update reservations.booking_types set price=800 where id='10000000-0000-4000-8000-000000000001'");
    assert.equal(query("select count(*) from reservations.bookings_operational where booking_type_id='10000000-0000-4000-8000-000000000001' and price_snapshot=800"),'4');
    assert.equal(query("select price_snapshot from reservations.bookings_operational where booking_number='OTHER-EVENT'"),'600.00');
    const participationBookings=JSON.parse(query("select public.list_conference_participations(gen_random_uuid(),'20000000-0000-4000-8000-000000000001')::text"));
    assert.equal(participationBookings.find(row=>row.bookingNumber==='FULL').priceSnapshot,800);
    assert.equal(query("select not has_table_privilege('anon','reservations.bookings_operational','select') and not has_table_privilege('authenticated','reservations.bookings_operational','select') and not has_table_privilege('service_role','reservations.bookings_operational','select')"),'t');
    assert.equal(query("select md5(string_agg(row_to_json(payment)::text,'|' order by payment.id)) from reservations.payments payment"),paymentState);
  }finally{
    command('dropdb',['--if-exists',database]);
  }
});
