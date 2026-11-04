do $$ declare s text;begin
select pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure) into s;
s:=replace(s,'''p_person_update_revision'',''p_gender'']','''p_person_update_revision'',''p_gender'',''p_date_of_birth'']');
s:=replace(s,'platform.people(full_name,phone,church,gender,created_by,updated_by)','platform.people(full_name,phone,church,gender,date_of_birth,created_by,updated_by)');
s:=replace(s,'nullif(p_args->>''p_gender'',''''),v_actor,v_actor)','nullif(p_args->>''p_gender'',''''),nullif(p_args->>''p_date_of_birth'','''')::date,v_actor,v_actor)');
s:=replace(s,'case when p_args ? ''p_gender'' then jsonb_build_object(''gender'',p_args->>''p_gender'') else ''{}''::jsonb end','case when p_args ? ''p_gender'' then jsonb_build_object(''gender'',p_args->>''p_gender'') else ''{}''::jsonb end || case when p_args ? ''p_date_of_birth'' then jsonb_build_object(''dateOfBirth'',p_args->>''p_date_of_birth'') else ''{}''::jsonb end');
execute s;end $$;;
