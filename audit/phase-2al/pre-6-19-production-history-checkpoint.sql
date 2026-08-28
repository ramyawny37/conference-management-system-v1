-- LAB_ONLY_PRODUCTION_HISTORY_RECONSTRUCTION
-- NOT PRODUCTION MIGRATION EXECUTION
-- NEVER EXECUTE AGAINST PRODUCTION OR DEVELOPMENT
begin;
do $guard$
declare column_contract text; constraint_contract text;
begin
  if current_setting('server_version_num')::integer/10000<>17
    or inet_server_addr() is null
    or inet_server_addr() not in (inet '127.0.0.1',inet '::1')
    or current_database()!~'^phase2a[[:alnum:]_]*$'
    or (select system_identifier::text from pg_control_system())='7662742571317219726' then
    raise exception 'LAB_ONLY_PRODUCTION_HISTORY_TARGET_REFUSED';
  end if;
  select string_agg(ordinal_position||':'||column_name||':'||udt_schema||'.'||udt_name||':'||is_nullable,
    ',' order by ordinal_position) into column_contract
  from information_schema.columns where table_schema='supabase_migrations'
    and table_name='schema_migrations';
  if column_contract<>'1:version:pg_catalog.text:NO,2:statements:pg_catalog._text:YES,3:name:pg_catalog.text:YES,4:created_by:pg_catalog.text:YES,5:idempotency_key:pg_catalog.text:YES,6:rollback:pg_catalog._text:YES' then
    raise exception 'LAB_ONLY_HISTORY_COLUMN_CONTRACT_MISMATCH';
  end if;
  select string_agg(contype::text||':'||pg_get_constraintdef(oid,true),',' order by contype)
    into constraint_contract from pg_constraint
    where conrelid=to_regclass('supabase_migrations.schema_migrations');
  if constraint_contract<>'p:PRIMARY KEY (version),u:UNIQUE (idempotency_key)' then
    raise exception 'LAB_ONLY_HISTORY_CONSTRAINT_CONTRACT_MISMATCH';
  end if;
  if (select count(*) from supabase_migrations.schema_migrations)<>0 then
    raise exception 'LAB_ONLY_HISTORY_EXPECTED_EMPTY';
  end if;
  if to_regprocedure('public.prevent_invalid_conference_organization_change()') is null
    or not exists(select 1 from pg_trigger where tgrelid='public.conferences'::regclass
      and tgname='conferences_prevent_invalid_organization_change' and not tgisinternal)
    or has_table_privilege('anon','public.conferences','insert,update,delete')
    or has_table_privilege('authenticated','public.conferences','insert,update,delete') then
    raise exception 'LAB_ONLY_HISTORY_6_18_CATALOG_CONTRACT_MISSING';
  end if;
end;
$guard$;
insert into supabase_migrations.schema_migrations
  (version,statements,name,created_by,idempotency_key,rollback)
values ('20260826191920',array[:'history_6_18_body']::text[],
  'conference_lifecycle_hardening_6_18_0',null,null,null);
do $post$
begin
  if (select count(*) from supabase_migrations.schema_migrations)<>1
    or not exists(select 1 from supabase_migrations.schema_migrations
      where version='20260826191920' and name='conference_lifecycle_hardening_6_18_0'
        and cardinality(statements)=1
        and md5(coalesce(array_to_string(statements,E'\n'),''))='699f1bf58271c8c75d6026ebc0436b28'
        and created_by is null and idempotency_key is null and rollback is null) then
    raise exception 'LAB_ONLY_HISTORY_6_18_POSTCONDITION_FAILED';
  end if;
end;
$post$;
commit;
