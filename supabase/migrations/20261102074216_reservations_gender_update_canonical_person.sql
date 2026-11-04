do $$
declare src text; needle text; patch text;
begin
select pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure) into src;
needle := 'update reservations.participants set full_name=';
patch := 'if p_args ? ''p_gender'' and nullif(p_args->>''p_gender'','''') is not null then '||
'perform public.require_effective_module_permission(p_device_id,''reservations'',''reservations.people.manage'',null,null); '||
'perform platform_private.update_canonical_person(p_device_id,v_actor,(select person_id from reservations.participants where id=v_booking.participant_id and scope_partition_id=v_booking.scope_partition_id),(select revision from platform.people where id=(select person_id from reservations.participants where id=v_booking.participant_id and scope_partition_id=v_booking.scope_partition_id)),jsonb_build_object(''fullName'',(select full_name from platform.people where id=(select person_id from reservations.participants where id=v_booking.participant_id and scope_partition_id=v_booking.scope_partition_id)),''gender'',p_args->>''p_gender''),v_operation_id,''reservations'',''reservations.people.manage'',jsonb_build_object(''eventId'',v_booking.event_id)); end if; ';
if (length(src)-length(replace(src,needle,'')))/length(needle)<>1 then raise exception 'Update location ambiguous';end if;
execute replace(src,needle,patch||needle);
end $$;;
