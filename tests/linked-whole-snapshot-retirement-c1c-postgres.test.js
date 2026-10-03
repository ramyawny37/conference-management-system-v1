'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const test=require('node:test');
const migration=path.resolve('supabase/migrations/20261009120000_retire_linked_whole_snapshot_infrastructure.sql');
const pgApp='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=fs.existsSync(path.join(pgApp,'psql'))?pgApp:'';
const database=`conference_c1c_${process.pid}_${Date.now()}`;
const connection=['-h',process.env.PGHOST||'/tmp','-p',process.env.PGPORT||'5432','-U',process.env.PGUSER||os.userInfo().username];
function command(name,args){return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe'}).trim();}
function query(sql){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',sql]);}
test('C1C migration executes destructively while canonical owners and Reservations remain intact',()=>{
  command('createdb',[database]);
  try{
    query(`create schema reservations;create table public.conferences(id uuid primary key);create table public.conference_participations(id uuid primary key,conference_id uuid);create table public.conference_accommodation_rooms(id uuid primary key,conference_id uuid);create table public.conference_accommodation_pricing(conference_id uuid primary key);create table public.conference_transport_vehicles(id uuid primary key,conference_id uuid);create table public.conference_restaurant_plans(conference_id uuid primary key);create table public.conference_air_conditioning(conference_id uuid primary key);create table public.conference_finance(conference_id uuid primary key);create table public.conference_branding(conference_id uuid primary key);create table reservations.bookings(id uuid primary key);create table public.conference_snapshots(conference_id uuid primary key,data jsonb);create table public.sync_operations(operation_id uuid primary key);create table public.sync_conflicts(id uuid primary key);create table public.conference_snapshot_guard_intents(operation_id uuid primary key);create function public.apply_conference_snapshot(uuid,uuid,uuid,bigint,jsonb,text,text) returns jsonb language sql as $$select '{}'::jsonb$$;create function public.device_guarded_get_conference_snapshot_metadata(uuid,uuid) returns jsonb language sql as $$select '{}'::jsonb$$;`);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',migration]);
    for(const name of ['conference_snapshots','sync_operations','sync_conflicts','conference_snapshot_guard_intents'])assert.equal(query(`select to_regclass('public.${name}') is null`),'t');
    assert.equal(query(`select to_regprocedure('public.apply_conference_snapshot(uuid,uuid,uuid,bigint,jsonb,text,text)') is null`),'t');
    assert.equal(query(`select to_regprocedure('public.device_guarded_get_conference_snapshot_metadata(uuid,uuid)') is null`),'t');
    for(const name of ['conferences','conference_participations','conference_accommodation_rooms','conference_accommodation_pricing','conference_transport_vehicles','conference_restaurant_plans','conference_air_conditioning','conference_finance','conference_branding'])assert.equal(query(`select to_regclass('public.${name}') is not null`),'t');
    assert.equal(query(`select to_regclass('reservations.bookings') is not null`),'t');
  }finally{command('dropdb',['--if-exists',database]);}
});
