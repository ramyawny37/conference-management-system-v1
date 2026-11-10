begin;

alter table public.system_bootstrap_state
  drop constraint if exists system_bootstrap_state_check;

alter table public.system_bootstrap_state
  add constraint system_bootstrap_state_check
  check (
    (
      completed_at is null
      and completed_by is null
      and device_id is null
      and operation_id is null
      and intent_hash is null
      and stored_result is null
    )
    or
    (
      completed_at is not null
      and completed_by is not null
      and operation_id is not null
      and intent_hash is not null
      and stored_result is not null
    )
  );

insert into public.system_bootstrap_state(singleton_id)
values (1)
on conflict (singleton_id) do nothing;

create or replace function public.complete_first_system_bootstrap(
  p_setup_token text,
  p_device_id uuid,
  p_device_name text,
  p_device_platform text,
  p_operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
 actor_id uuid:=auth.uid();
 state_row public.system_bootstrap_state%rowtype;
 secret_row public.system_bootstrap_secret%rowtype;
 intent text;
 result jsonb;
 role_id uuid;
 display_name text;
begin
 if actor_id is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 if p_operation_id is null then raise exception 'INVALID_BOOTSTRAP_REQUEST' using errcode='22023'; end if;
 intent:=pg_catalog.encode(extensions.digest(actor_id::text,'sha256'),'hex');
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('first-system-bootstrap',0));

 insert into public.system_bootstrap_state(singleton_id) values(1) on conflict(singleton_id) do nothing;
 select * into strict state_row from public.system_bootstrap_state where singleton_id=1 for update;

 if state_row.completed_at is not null then
  if state_row.completed_by=actor_id and state_row.operation_id=p_operation_id and state_row.intent_hash=intent then return state_row.stored_result; end if;
  raise exception 'BOOTSTRAP_ALREADY_COMPLETED' using errcode='42501';
 end if;
 if exists(select 1 from platform.user_roles a join platform.roles r on r.id=a.role_id where r.domain='platform' and r.code='platform_owner' and a.revoked_at is null) then raise exception 'SYSTEM_OWNER_ALREADY_EXISTS' using errcode='42501'; end if;

 select * into secret_row from public.system_bootstrap_secret where singleton_id=1 for update;
 if not found or secret_row.intended_user_id<>actor_id then raise exception 'BOOTSTRAP_IDENTITY_INVALID' using errcode='42501'; end if;
 if extensions.crypt(coalesce(p_setup_token,''),secret_row.secret_hash)<>secret_row.secret_hash then raise exception 'BOOTSTRAP_CREDENTIAL_INVALID' using errcode='42501'; end if;

 select nullif(pg_catalog.btrim(coalesce(raw_user_meta_data->>'display_name',raw_user_meta_data->>'name','')),'')
 into display_name from auth.users where id=actor_id;
 if not found then raise exception 'AUTH_USER_NOT_FOUND' using errcode='P0002'; end if;

 insert into platform.profiles(user_id,display_name,account_status,status_changed_at,status_changed_by,approved_at,approved_by)
 values(actor_id,display_name,'approved',pg_catalog.now(),actor_id,pg_catalog.now(),actor_id)
 on conflict(user_id) do update set
  display_name=coalesce(platform.profiles.display_name,excluded.display_name),
  account_status='approved',status_reason='first platform owner bootstrap',
  status_changed_at=pg_catalog.now(),status_changed_by=actor_id,
  approved_at=pg_catalog.now(),approved_by=actor_id,blocked_at=null,blocked_by=null;

 select id into role_id from platform.roles where domain='platform' and code='platform_owner';
 if role_id is null then raise exception 'REFERENCE_DATA_NOT_SEEDED' using errcode='55000'; end if;
 insert into platform.user_roles(user_id,role_id,scope_type,scope_id,granted_by,metadata)
 values(actor_id,role_id,'platform',null,actor_id,pg_catalog.jsonb_build_object('bootstrap',true))
 on conflict do nothing;

 result:=pg_catalog.jsonb_build_object('status','completed','operationId',p_operation_id);
 update public.system_bootstrap_state
 set completed_at=pg_catalog.now(),completed_by=actor_id,device_id=null,
     operation_id=p_operation_id,intent_hash=intent,stored_result=result
 where singleton_id=1;
 if not found then raise exception 'BOOTSTRAP_STATE_WRITE_FAILED' using errcode='55000'; end if;

 delete from public.system_bootstrap_secret where singleton_id=1;
 perform platform_private.write_audit_event(actor_id,actor_id,'platform','bootstrap','platform.bootstrap_completed','profile',actor_id,'platform',null,pg_catalog.jsonb_build_object('accountStatus','approved','role','platform_owner'),pg_catalog.jsonb_build_object('bootstrap',true,'deviceEnrollment','p256_followup'),null,null,'bootstrap');
 return result;
end
$function$;

do $$
declare body text;
begin
 select pg_get_functiondef(p.oid) into body
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='complete_first_system_bootstrap'
 and pg_get_function_identity_arguments(p.oid)='p_setup_token text, p_device_id uuid, p_device_name text, p_device_platform text, p_operation_id uuid';
 if body is null
    or body not like '%insert into public.system_bootstrap_state(singleton_id)%'
    or body not like '%BOOTSTRAP_STATE_WRITE_FAILED%'
    or body not like '%device_id=null%' then
   raise exception 'FIRST_SYSTEM_BOOTSTRAP_STATE_INVARIANT_CUTOVER_FAILED' using errcode='55000';
 end if;
end $$;

commit;
