do $$
declare source text; old text;
begin
select pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure) into source;
old := 'array[''p_person_id'',''p_person_update_revision'']';
if source not like '%'||old||'%' then raise exception 'Create contract missing';end if;
execute replace(source,old,'array[''p_person_id'',''p_person_update_revision'',''p_gender'']');
end $$;;
