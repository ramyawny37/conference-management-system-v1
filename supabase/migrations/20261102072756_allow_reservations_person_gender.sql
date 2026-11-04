do $$
declare v text; a text; b text;
begin
select pg_get_functiondef('platform_private.update_canonical_person(uuid,uuid,uuid,bigint,jsonb,uuid,text,text,jsonb)'::regprocedure) into v;
a:='v_allowed:=array[''fullName'',''phone'',''church''];';
b:='v_allowed:=array[''fullName'',''phone'',''church'',''gender''];';
if position(a in v)=0 then raise exception 'Unexpected person update contract';end if;
execute replace(v,a,b);
end $$;;
