-- New authenticated users enter Platform canonical account storage directly.
create or replace function public.handle_new_user_profile()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_display_name text:=nullif(pg_catalog.btrim(coalesce(new.raw_user_meta_data->>'display_name',new.raw_user_meta_data->>'name','')),'');
begin
 insert into public.profiles(id,display_name) values(new.id,v_display_name)
 on conflict(id) do update set display_name=coalesce(public.profiles.display_name,excluded.display_name);
 insert into platform.profiles(user_id,display_name,account_status) values(new.id,v_display_name,'pending')
 on conflict(user_id) do update set display_name=coalesce(platform.profiles.display_name,excluded.display_name);
 return new;
end $$;
