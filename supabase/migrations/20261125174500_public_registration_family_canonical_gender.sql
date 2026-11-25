begin;

do $patch$
declare d text;old_text text:=
$$if nullif(btrim(v_member->>'fullName'),'') is null or nullif(v_member->>'dateOfBirth','') is null then raise exception 'PUBLIC_REGISTRATION_MEMBER_IDENTITY_REQUIRED' using errcode='22023';end if;$$;
new_text text:=
$$if nullif(btrim(v_member->>'fullName'),'') is null or nullif(v_member->>'dateOfBirth','') is null or (v_member->>'gender') not in('male','female') then raise exception 'PUBLIC_REGISTRATION_MEMBER_IDENTITY_REQUIRED' using errcode='22023';end if;$$;
begin
 d:=pg_get_functiondef('reservations.public_registration_submit_family(uuid,uuid,bytea,bytea,jsonb)'::regprocedure);
 if (length(d)-length(replace(d,old_text,'')))/length(old_text)<>1 then
  raise exception 'PUBLIC_REGISTRATION_FAMILY_GENDER_WRITER_DRIFT';
 end if;
 execute replace(d,old_text,new_text);
end $patch$;

commit;
