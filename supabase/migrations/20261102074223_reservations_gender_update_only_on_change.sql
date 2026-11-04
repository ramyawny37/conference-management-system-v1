do $$
declare src text; old text; replacement text;
begin
select pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure) into src;
old := 'if p_args ? ''p_gender'' and nullif(p_args->>''p_gender'','''') is not null then perform public.require_effective_module_permission';
replacement := 'if p_args ? ''p_gender'' and nullif(p_args->>''p_gender'','''') is not null and (select gender from platform.people where id=(select person_id from reservations.participants where id=v_booking.participant_id and scope_partition_id=v_booking.scope_partition_id)) is distinct from (p_args->>''p_gender'') then perform public.require_effective_module_permission';
if position(old in src)=0 then raise exception 'Gender update guard missing';end if;
execute replace(src,old,replacement);
end $$;;
