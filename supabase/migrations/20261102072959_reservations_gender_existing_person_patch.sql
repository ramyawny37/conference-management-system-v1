do $$
declare source text; old text;
begin
select pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure) into source;
old := 'jsonb_build_object(''fullName'',p_args->>''p_full_name'',''phone'',p_args->>''p_phone'',''church'',p_args->>''p_church'')';
if source not like '%'||old||'%' then raise exception 'Person patch missing';end if;
execute replace(source,old,old||' || case when p_args ? ''p_gender'' then jsonb_build_object(''gender'',p_args->>''p_gender'') else ''{}''::jsonb end');
end $$;;
