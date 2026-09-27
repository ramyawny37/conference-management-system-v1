'use strict';

const assert=require('node:assert/strict');
const {execFileSync}=require('node:child_process');
const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');

const root=path.join(__dirname,'..');
const migration=path.join(root,'supabase/migrations/20260926160000_reservations_legacy_organization_ownership_reconciliation.sql');
const sql=fs.readFileSync(migration,'utf8');
const pgBin='/Applications/Postgres.app/Contents/Versions/latest/bin';
const psql=path.join(pgBin,'psql');
const createdb=path.join(pgBin,'createdb');
const dropdb=path.join(pgBin,'dropdb');
const database=`reservations_legacy_org_${process.pid}_${Date.now()}`;

function run(args,options={}) {
  return execFileSync(args[0],args.slice(1),{encoding:'utf8',stdio:options.stdio||'pipe'}).trim();
}
function query(statement) {
  return run([psql,'-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement]);
}
function applyMigration() {
  return run([psql,'-X','-v','ON_ERROR_STOP=1','-d',database,'-f',migration]);
}

test('migration is narrowly scoped and preserves immutable history contracts',()=>{
  assert.deepEqual([...sql.matchAll(/update\s+reservations\.(\w+)/gi)].map(x=>x[1]).sort(),['booking_types','bookings','participants']);
  assert.doesNotMatch(sql,/reservations\.(event_periods|operational_reviews|payments)/i);
  assert.doesNotMatch(sql,/update\s+reservations\.events/i);
  assert.match(sql,/^begin;/);
  assert.match(sql,/commit;\s*$/);
  assert.ok(sql.indexOf('end $$;')<sql.search(/update\s+reservations/i));
  const active=fs.readFileSync(path.join(root,'supabase/migrations/20260924223000_reservations_participant_booking_type_edit.sql'),'utf8');
  assert.match(active,/where id=v_booking.participant_id and scope_partition_id=v_booking.scope_partition_id and organization_id is not distinct from v_booking.organization_id/);
  assert.doesNotMatch(sql,/set\s+(?:id|scope_partition_id|booking_number|revision|updated_at|updated_by)\s*=/i);
  assert.doesNotMatch(sql,/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i);
  for(const table of ['bookings','participants','booking_types']) {
    assert.match(sql,new RegExp(`update\\s+reservations\\.${table}\\b`,'i'));
  }
  for(const guard of [
    'RESERVATIONS_LEGACY_ORGANIZATION_ORPHAN',
    'RESERVATIONS_LEGACY_ORGANIZATION_PARTITION_MISMATCH',
    'RESERVATIONS_LEGACY_ORGANIZATION_CONFLICT',
    'RESERVATIONS_LEGACY_PARTICIPANT_ORGANIZATION_AMBIGUOUS'
  ]) assert.match(sql,new RegExp(guard));
});

test('isolated reconciliation and active booking/participant ownership predicate reproduction preserve all excluded data',
  {skip:!fs.existsSync(psql)||!fs.existsSync(createdb)||!fs.existsSync(dropdb)},()=>{
  run([createdb,database]);
  try {
    query(`
      create schema reservations;
      create schema reservations_private;
      create table reservations.events(id uuid primary key,organization_id uuid,scope_partition_id uuid not null);
      create table reservations.event_periods(id uuid primary key,organization_id uuid,event_id uuid not null,scope_partition_id uuid not null,kind text,revision bigint,updated_at timestamptz,updated_by uuid);
      create table reservations.booking_types(id uuid primary key,organization_id uuid,event_id uuid not null,scope_partition_id uuid not null,name text,price numeric,revision bigint,updated_at timestamptz,updated_by uuid);
      create table reservations.participants(id uuid primary key,organization_id uuid,scope_partition_id uuid not null,full_name text,revision bigint,updated_at timestamptz,updated_by uuid);
      create table reservations.bookings(id uuid primary key,organization_id uuid,event_id uuid not null,participant_id uuid not null,booking_type_id uuid not null,scope_partition_id uuid not null,booking_number text,price_snapshot numeric,notes text,revision bigint,updated_at timestamptz,updated_by uuid);
      create table reservations.operational_reviews(id uuid primary key,organization_id uuid,booking_id uuid not null,scope_partition_id uuid not null,review_status text,revision bigint,updated_at timestamptz,updated_by uuid);
      create table reservations.payments(id uuid primary key,organization_id uuid,booking_id uuid not null,scope_partition_id uuid not null,amount numeric,status text,history jsonb);
      alter table reservations.bookings
        add constraint "Historical Number Key" unique(organization_id,booking_number),
        add constraint canonical_partition_number unique(scope_partition_id,booking_number),
        add constraint preserved_partition_id unique(scope_partition_id,id),
        add constraint preserved_organization_id unique(organization_id,id),
        add constraint preserved_three_column_key unique(organization_id,booking_number,id),
        add constraint preserved_event_fk foreign key(event_id) references reservations.events(id);
      alter table reservations.payments add constraint preserved_payment_booking_fk
        foreign key(booking_id) references reservations.bookings(id);
      insert into reservations.events values
        ('10000000-0000-0000-0000-000000000001','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','10000000-0000-0000-0000-000000000001'),
        ('20000000-0000-0000-0000-000000000002','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','10000000-0000-0000-0000-000000000001'),
        ('30000000-0000-0000-0000-000000000003',null,'30000000-0000-0000-0000-000000000003');
      insert into reservations.event_periods values
        ('11000000-0000-0000-0000-000000000001',null,'10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','conference',7,'2026-01-01','cccccccc-cccc-cccc-cccc-cccccccccccc');
      insert into reservations.booking_types values
        ('12000000-0000-0000-0000-000000000099',null,'10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Unused legacy type',300,6,'2026-01-03','cccccccc-cccc-cccc-cccc-cccccccccccc'),
        ('12000000-0000-0000-0000-000000000001',null,'10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Legacy',125,9,'2026-01-02','cccccccc-cccc-cccc-cccc-cccccccccccc'),
        ('12000000-0000-0000-0000-000000000002','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Correct',250,4,'2026-01-03','cccccccc-cccc-cccc-cccc-cccccccccccc'),
        ('32000000-0000-0000-0000-000000000003',null,'30000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000003','Standalone',50,3,'2026-01-04','cccccccc-cccc-cccc-cccc-cccccccccccc');
      insert into reservations.participants values
        ('13000000-0000-0000-0000-000000000001',null,'10000000-0000-0000-0000-000000000001','Legacy Person',11,'2026-01-05','cccccccc-cccc-cccc-cccc-cccccccccccc'),
        ('33000000-0000-0000-0000-000000000003',null,'30000000-0000-0000-0000-000000000003','Standalone Person',5,'2026-01-06','cccccccc-cccc-cccc-cccc-cccccccccccc');
      insert into reservations.bookings values
        ('14000000-0000-0000-0000-000000000001',null,'10000000-0000-0000-0000-000000000001','13000000-0000-0000-0000-000000000001','12000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','RES-2026-0001',125,'legacy note',13,'2026-01-07','cccccccc-cccc-cccc-cccc-cccccccccccc'),
        ('34000000-0000-0000-0000-000000000003',null,'30000000-0000-0000-0000-000000000003','33000000-0000-0000-0000-000000000003','32000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000003','RES-2026-0003',50,'standalone note',2,'2026-01-08','cccccccc-cccc-cccc-cccc-cccccccccccc');
      insert into reservations.operational_reviews values
        ('15000000-0000-0000-0000-000000000001',null,'14000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','pending',17,'2026-01-09','cccccccc-cccc-cccc-cccc-cccccccccccc');
      insert into reservations.payments values
        ('16000000-0000-0000-0000-000000000001',null,'14000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',75,'active','{"source":"legacy"}');
      insert into reservations.events values
        ('50000000-0000-0000-0000-000000000005','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','50000000-0000-0000-0000-000000000005');
      insert into reservations.booking_types values
        ('52000000-0000-0000-0000-000000000005',null,'50000000-0000-0000-0000-000000000005','50000000-0000-0000-0000-000000000005','Other partition',125,3,'2026-01-02','cccccccc-cccc-cccc-cccc-cccccccccccc');
      insert into reservations.participants values
        ('53000000-0000-0000-0000-000000000005',null,'50000000-0000-0000-0000-000000000005','Other partition person',4,'2026-01-05','cccccccc-cccc-cccc-cccc-cccccccccccc');
      insert into reservations.bookings values
        ('54000000-0000-0000-0000-000000000005',null,'50000000-0000-0000-0000-000000000005','53000000-0000-0000-0000-000000000005','52000000-0000-0000-0000-000000000005','50000000-0000-0000-0000-000000000005','RES-2026-0001',125,'other partition note',8,'2026-01-07','cccccccc-cccc-cccc-cccc-cccccccccccc');
      create table reservations.test_before_rows as select
        (select to_jsonb(x) from reservations.event_periods x where id='11000000-0000-0000-0000-000000000001') period,
        (select to_jsonb(x)-'organization_id' from reservations.booking_types x where id='12000000-0000-0000-0000-000000000001') booking_type,
        (select to_jsonb(x)-'organization_id' from reservations.participants x where id='13000000-0000-0000-0000-000000000001') participant,
        (select to_jsonb(x)-'organization_id' from reservations.bookings x where id='14000000-0000-0000-0000-000000000001') booking,
        (select to_jsonb(x) from reservations.operational_reviews x where id='15000000-0000-0000-0000-000000000001') review,
        (select to_jsonb(x) from reservations.payments x where id='16000000-0000-0000-0000-000000000001') payment;
    `);
    const constraintKeys=()=>JSON.parse(query(`select coalesce(jsonb_agg(jsonb_build_object(
      'oid',c.oid,'table',c.conrelid::regclass::text,'name',c.conname,'type',c.contype,
      'definition',pg_get_constraintdef(c.oid),
      'columns',array(select a.attname::text from unnest(c.conkey) k(attnum)
        join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.attnum order by a.attname::text)
      ) order by c.oid),'[]'::jsonb)
      from pg_constraint c where c.connamespace='reservations'::regnamespace`));
    const isNumberKey=(c,column)=>c.table==='reservations.bookings'&&c.type==='u'
      &&JSON.stringify(c.columns)===JSON.stringify(['booking_number',column]);
    const constraintsBefore=constraintKeys();
    assert.equal(constraintsBefore.filter(c=>isNumberKey(c,'organization_id')).length,1);
    assert.equal(constraintsBefore.filter(c=>isNumberKey(c,'scope_partition_id')).length,1);
    const bookingRowsBefore=query(`select jsonb_agg(to_jsonb(b)-'organization_id' order by id) from reservations.bookings b`);
    assert.throws(()=>query(`update reservations.bookings b set organization_id=e.organization_id
      from reservations.events e where e.id=b.event_id and b.organization_id is null and e.organization_id is not null`),/duplicate key value violates unique constraint "Historical Number Key"/);
    assert.equal(query(`select count(*) from reservations.bookings where booking_number='RES-2026-0001' and organization_id is null`),'2');
    const excludedSnapshot=()=>query(`select jsonb_build_object(
      'unusedType',(select to_jsonb(x) from reservations.booking_types x where id='12000000-0000-0000-0000-000000000099'),
      'events',(select jsonb_agg(to_jsonb(x) order by id) from reservations.events x),
      'periods',(select jsonb_agg(to_jsonb(x) order by id) from reservations.event_periods x),
      'reviews',(select jsonb_agg(to_jsonb(x) order by id) from reservations.operational_reviews x),
      'payments',(select jsonb_agg(to_jsonb(x) order by id) from reservations.payments x),
      'standaloneBooking',(select to_jsonb(x) from reservations.bookings x where id='34000000-0000-0000-0000-000000000003'))`);
    const excludedBefore=excludedSnapshot();
    const ownershipPredicate=`select exists(select 1 from reservations.bookings b
      join reservations.participants p on p.id=b.participant_id
        and p.scope_partition_id=b.scope_partition_id
        and p.organization_id is not distinct from b.organization_id
      where b.id='14000000-0000-0000-0000-000000000001'
        and b.organization_id is not distinct from 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid)`;
    assert.equal(query(ownershipPredicate),'f','active booking/participant ownership predicate reproduction before repair');
    applyMigration();
    const constraintsAfter=constraintKeys();
    assert.equal(constraintsAfter.filter(c=>isNumberKey(c,'organization_id')).length,0);
    assert.equal(constraintsAfter.filter(c=>isNumberKey(c,'scope_partition_id')).length,1);
    assert.deepEqual(constraintsAfter,constraintsBefore.filter(c=>!isNumberKey(c,'organization_id')),
      'every unrelated constraint, including primary/foreign keys, retains its OID and definition');
    assert.equal(query(`select count(*)=2 and count(distinct scope_partition_id)=2
      and bool_and(organization_id is not distinct from 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid)
      from reservations.bookings where booking_number='RES-2026-0001'`),'t');
    assert.equal(query(`select jsonb_agg(to_jsonb(b)-'organization_id' order by id) from reservations.bookings b`),bookingRowsBefore);
    assert.equal(query(`select organization_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' from reservations.participants where id='53000000-0000-0000-0000-000000000005'`),'t');
    assert.equal(query(`select organization_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' from reservations.booking_types where id='52000000-0000-0000-0000-000000000005'`),'t');
    assert.throws(()=>query(`update reservations.bookings set scope_partition_id='10000000-0000-0000-0000-000000000001' where id='54000000-0000-0000-0000-000000000005'`),/duplicate key value violates unique constraint "canonical_partition_number"/);
    assert.equal(query(`select bool_and(organization_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') from (
      select organization_id from reservations.booking_types where id='12000000-0000-0000-0000-000000000001' union all
      select organization_id from reservations.participants where id='13000000-0000-0000-0000-000000000001' union all
      select organization_id from reservations.bookings where id='14000000-0000-0000-0000-000000000001') x`),'t');
    assert.equal(query(`select organization_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' from reservations.booking_types where id='12000000-0000-0000-0000-000000000002'`),'t');
    assert.equal(query(`select organization_id is null from reservations.booking_types where id='32000000-0000-0000-0000-000000000003'`),'t');
    assert.equal(query(`select organization_id is null from reservations.participants where id='33000000-0000-0000-0000-000000000003'`),'t');
    assert.equal(query(`select
      (select to_jsonb(x) from reservations.event_periods x where id='11000000-0000-0000-0000-000000000001')=period and
      (select to_jsonb(x)-'organization_id' from reservations.booking_types x where id='12000000-0000-0000-0000-000000000001')=booking_type and
      (select to_jsonb(x)-'organization_id' from reservations.participants x where id='13000000-0000-0000-0000-000000000001')=participant and
      (select to_jsonb(x)-'organization_id' from reservations.bookings x where id='14000000-0000-0000-0000-000000000001')=booking and
      (select to_jsonb(x) from reservations.operational_reviews x where id='15000000-0000-0000-0000-000000000001')=review and
      (select to_jsonb(x) from reservations.payments x where id='16000000-0000-0000-0000-000000000001')=payment
      from reservations.test_before_rows`),'t');
    assert.equal(query(`select organization_id is null from reservations.booking_types where id='12000000-0000-0000-0000-000000000099'`),'t','unused NULL-owned type under an organization-owned Event remains untouched');
    assert.equal(excludedSnapshot(),excludedBefore);
    assert.equal(query(ownershipPredicate),'t','active booking/participant ownership predicate reproduction after repair');

    const versions=query(`select tableoid::regclass::text||':'||id||':'||xmin from reservations.bookings union all select tableoid::regclass::text||':'||id||':'||xmin from reservations.participants union all select tableoid::regclass::text||':'||id||':'||xmin from reservations.booking_types order by 1`);
    applyMigration();
    assert.deepEqual(constraintKeys(),constraintsAfter);
    assert.equal(query(`select tableoid::regclass::text||':'||id||':'||xmin from reservations.bookings union all select tableoid::regclass::text||':'||id||':'||xmin from reservations.participants union all select tableoid::regclass::text||':'||id||':'||xmin from reservations.booking_types order by 1`),versions);

    query(`insert into reservations.participants values('23000000-0000-0000-0000-000000000009',null,'10000000-0000-0000-0000-000000000001','Ambiguous',1,now(),null);
      insert into reservations.bookings values
      ('24000000-0000-0000-0000-000000000009',null,'10000000-0000-0000-0000-000000000001','23000000-0000-0000-0000-000000000009','12000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','A',1,null,1,now(),null),
      ('24000000-0000-0000-0000-000000000010',null,'20000000-0000-0000-0000-000000000002','23000000-0000-0000-0000-000000000009','12000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','B',1,null,1,now(),null)`);
    const ambiguousBefore=query('select jsonb_agg(to_jsonb(b) order by id) from reservations.bookings b');
    assert.throws(()=>applyMigration(),/RESERVATIONS_LEGACY_PARTICIPANT_ORGANIZATION_AMBIGUOUS/);
    assert.equal(query('select jsonb_agg(to_jsonb(b) order by id) from reservations.bookings b'),ambiguousBefore);
    query(`delete from reservations.bookings where participant_id='23000000-0000-0000-0000-000000000009'; delete from reservations.participants where id='23000000-0000-0000-0000-000000000009'`);
    query(`update reservations.bookings set organization_id=null where id='14000000-0000-0000-0000-000000000001'; update reservations.participants set organization_id='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' where id='13000000-0000-0000-0000-000000000001'`);
    assert.throws(()=>applyMigration(),/RESERVATIONS_LEGACY_ORGANIZATION_CONFLICT/);
    query(`update reservations.participants set organization_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' where id='13000000-0000-0000-0000-000000000001';
      update reservations.bookings set booking_type_id='42000000-0000-0000-0000-000000000004' where id='14000000-0000-0000-0000-000000000001'`);
    assert.throws(()=>applyMigration(),/RESERVATIONS_LEGACY_ORGANIZATION_ORPHAN/);
    query(`update reservations.bookings set booking_type_id='12000000-0000-0000-0000-000000000001',scope_partition_id='30000000-0000-0000-0000-000000000003' where id='14000000-0000-0000-0000-000000000001'`);
    assert.throws(()=>applyMigration(),/RESERVATIONS_LEGACY_ORGANIZATION_PARTITION_MISMATCH/);
    assert.equal(query(`select organization_id is null from reservations.bookings where id='14000000-0000-0000-0000-000000000001'`),'t');
    query(`update reservations.bookings set scope_partition_id='10000000-0000-0000-0000-000000000001' where id='14000000-0000-0000-0000-000000000001';
      insert into reservations.booking_types values('42000000-0000-0000-0000-000000000004',null,'40000000-0000-0000-0000-000000000004','40000000-0000-0000-0000-000000000004','Unrelated orphan',1,1,now(),null)`);
    applyMigration();
    assert.equal(query(`select organization_id is null from reservations.booking_types where id='42000000-0000-0000-0000-000000000004'`),'t');
    assert.equal(excludedSnapshot(),excludedBefore);
    // Fully owned, unrelated historical conflict/partition residue is not audited.
    query(`update reservations.booking_types set organization_id='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',scope_partition_id='30000000-0000-0000-0000-000000000003' where id='12000000-0000-0000-0000-000000000002'`);
    applyMigration();
  } finally {
    run([dropdb,'--if-exists',database]);
  }
});
