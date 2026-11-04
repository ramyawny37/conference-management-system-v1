do $$ declare s text;begin
select pg_get_functiondef('platform_private.update_canonical_person(uuid,uuid,uuid,bigint,jsonb,uuid,text,text,jsonb)'::regprocedure) into s;
if position('array[''fullName'',''phone'',''church'',''gender''];' in s)=0 then raise exception 'contract changed';end if;
execute replace(s,'array[''fullName'',''phone'',''church'',''gender''];','array[''fullName'',''phone'',''church'',''gender'',''dateOfBirth''];');
end $$;;
