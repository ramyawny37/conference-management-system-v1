do $$
declare source text; old text;
begin
select pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure) into source;
old := 'insert into platform.people(full_name,phone,church,created_by,updated_by) values(';
if position(old in source)=0 then raise exception 'Insert header missing';end if;
source:=replace(source,old,'insert into platform.people(full_name,phone,church,gender,created_by,updated_by) values(');
old := ',v_actor,v_actor) returning id into v_person_id;';
if position(old in source)=0 then raise exception 'Insert tail missing';end if;
execute replace(source,old,',nullif(p_args->>''p_gender'',''''),v_actor,v_actor) returning id into v_person_id;');
end $$;;
