\pset format unaligned
\pset tuples_only on
with target_relations(name) as (values
 ('webauthn_privileged_device_feature'),('device_security_credentials'),
 ('device_possession_challenges'),('device_possession_challenge_consumers'),
 ('privileged_device_listing_sessions'),
 ('system_owner_credential_bootstrap_authorizations'),
 ('system_owner_credential_recovery_authorizations'),
 ('privileged_device_authorization_audit_log'),
 ('system_owner_device_authorization_operations')
), columns_component as (
 select coalesce(jsonb_agg(jsonb_build_object(
   'schema',n.nspname,'relation',c.relname,'ordinal',a.attnum,'name',a.attname,
   'type',format_type(a.atttypid,a.atttypmod),'type_schema',tn.nspname,
   'type_name',t.typname,'array_element',case when t.typelem<>0 then
     format_type(t.typelem,null) end,'domain',case when t.typtype='d' then
     format_type(t.oid,null) end,'nullable',not a.attnotnull,
   'default',pg_get_expr(d.adbin,d.adrelid),'identity',a.attidentity,
   'generated',a.attgenerated,'collation',case when a.attcollation<>0 then
     (select cn.nspname||'.'||co.collname from pg_collation co join pg_namespace cn
       on cn.oid=co.collnamespace where co.oid=a.attcollation) end)
   order by n.nspname,c.relname,a.attnum),'[]'::jsonb) value
 from target_relations r join pg_class c on c.relname=r.name
 join pg_namespace n on n.oid=c.relnamespace and n.nspname='public'
 join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
 join pg_type t on t.oid=a.atttypid join pg_namespace tn on tn.oid=t.typnamespace
 left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum
), constraints_component as (
 select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,
   'relation',c.relname,'name',x.conname,'type',x.contype,
   'definition',regexp_replace(pg_get_constraintdef(x.oid,false),'[[:space:]]+',' ','g'),
   'referenced_relation',case when x.confrelid<>0 then x.confrelid::regclass::text end)
   order by n.nspname,c.relname,x.conname),'[]'::jsonb) value
 from target_relations r join pg_class c on c.relname=r.name
 join pg_namespace n on n.oid=c.relnamespace and n.nspname='public'
 join pg_constraint x on x.conrelid=c.oid
), indexes_component as (
 select coalesce(jsonb_agg(jsonb_build_object('schema',i.schemaname,
   'relation',i.tablename,'name',i.indexname,'definition',
   regexp_replace(i.indexdef,'[[:space:]]+',' ','g'))
   order by i.schemaname,i.tablename,i.indexname),'[]'::jsonb) value
 from target_relations r join pg_indexes i on i.schemaname='public' and i.tablename=r.name
), triggers_component as (
 select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,
   'relation',c.relname,'name',g.tgname,'definition',
   regexp_replace(pg_get_triggerdef(g.oid,false),'[[:space:]]+',' ','g'),
   'function',g.tgfoid::regprocedure::text)
   order by n.nspname,c.relname,g.tgname),'[]'::jsonb) value
 from target_relations r join pg_class c on c.relname=r.name
 join pg_namespace n on n.oid=c.relnamespace and n.nspname='public'
 join pg_trigger g on g.tgrelid=c.oid and not g.tgisinternal
), functions_component as (
 select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'name',p.proname,
   'arguments',pg_get_function_identity_arguments(p.oid),
   'return_type',pg_get_function_result(p.oid),'language',l.lanname,
   'volatility',p.provolatile,'parallel',p.proparallel,'strict',p.proisstrict,
   'security_definer',p.prosecdef,'owner',o.rolname,'config',p.proconfig,
   'source',regexp_replace(p.prosrc,'[[:space:]]+',' ','g'),
   'definition',regexp_replace(pg_get_functiondef(p.oid),'[[:space:]]+',' ','g'),
   'acl',(select coalesce(jsonb_agg(jsonb_build_object('grantee',case when e.grantee=0
     then 'PUBLIC' else gr.rolname end,'grantor',go.rolname,'privilege',e.privilege_type,
     'grantable',e.is_grantable) order by e.grantee,e.privilege_type),'[]'::jsonb)
     from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) e
     left join pg_roles gr on gr.oid=e.grantee join pg_roles go on go.oid=e.grantor))
   order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)),'[]'::jsonb) value
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
 join pg_language l on l.oid=p.prolang join pg_roles o on o.oid=p.proowner
 where p.prosrc ~ '(webauthn|device_security|device_possession|privileged_device|credential_bootstrap|credential_recovery)'
    or p.proname ~ '(webauthn|device_security|device_possession|privileged_device|credential_bootstrap|credential_recovery)'
), security_component as (
 select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname,
   'owner',o.rolname,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
   'policies',(select coalesce(jsonb_agg(jsonb_build_object('name',pol.polname,
     'command',pol.polcmd,'roles',(select jsonb_agg(coalesce(pr.rolname,'PUBLIC') order by x)
       from unnest(pol.polroles) x left join pg_roles pr on pr.oid=x),
     'using',pg_get_expr(pol.polqual,pol.polrelid),'check',pg_get_expr(pol.polwithcheck,pol.polrelid))
     order by pol.polname),'[]'::jsonb) from pg_policy pol where pol.polrelid=c.oid),
   'acl',(select coalesce(jsonb_agg(jsonb_build_object('grantee',case when e.grantee=0
     then 'PUBLIC' else gr.rolname end,'grantor',go.rolname,'privilege',e.privilege_type,
     'grantable',e.is_grantable) order by e.grantee,e.privilege_type),'[]'::jsonb)
     from aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) e
     left join pg_roles gr on gr.oid=e.grantee join pg_roles go on go.oid=e.grantor))
   order by n.nspname,c.relname),'[]'::jsonb) value
 from target_relations r join pg_class c on c.relname=r.name
 join pg_namespace n on n.oid=c.relnamespace and n.nspname='public'
 join pg_roles o on o.oid=c.relowner
), components as (
 select 'columns' name,value from columns_component union all
 select 'constraints',value from constraints_component union all
 select 'indexes',value from indexes_component union all
 select 'triggers',value from triggers_component union all
 select 'functions',value from functions_component union all
 select 'security',value from security_component
), hashes as (
 select name,value,encode(sha256(convert_to(value::text,'UTF8')),'hex') hash from components
)
select jsonb_build_object('postgres_version',current_setting('server_version'),
  'database',current_database(),'components',(select jsonb_object_agg(name,value) from hashes),
  'hashes',(select jsonb_object_agg(name,hash) from hashes),
  'combined_sha256',(select encode(sha256(convert_to(string_agg(name||'='||hash,E'\n' order by name),'UTF8')),'hex') from hashes))::text;
