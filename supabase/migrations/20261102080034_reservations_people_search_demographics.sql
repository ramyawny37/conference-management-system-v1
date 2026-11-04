do $$
declare src text; old text;
begin
select pg_get_functiondef('public.search_reservations_people(uuid,text,integer)'::regprocedure) into src;
old := '''church'',p.church,''revision'',p.revision';
if position(old in src)=0 then raise exception 'Search projection changed';end if;
execute replace(src,old,'''church'',p.church,''gender'',p.gender,''dateOfBirth'',p.date_of_birth,''revision'',p.revision');
end $$;;
