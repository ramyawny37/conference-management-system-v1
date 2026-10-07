-- First-setup completion is determined by canonical Platform owner authority.
create or replace function public.get_first_system_bootstrap_status()
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); intended_id uuid;
begin
 if actor_id is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 if exists(select 1 from platform.user_roles a join platform.roles r on r.id=a.role_id where r.domain='platform' and r.code='platform_owner' and a.revoked_at is null)
   or exists(select 1 from public.system_bootstrap_state where singleton_id=1 and completed_at is not null) then
  return pg_catalog.jsonb_build_object('status','completed','setupRequired',false);
 end if;
 select intended_user_id into intended_id from public.system_bootstrap_secret where singleton_id=1;
 if not found then return pg_catalog.jsonb_build_object('status','not_provisioned','setupRequired',false); end if;
 if intended_id<>actor_id then return pg_catalog.jsonb_build_object('status','not_authorized','setupRequired',false); end if;
 return pg_catalog.jsonb_build_object('status','setup_required','setupRequired',true);
end $$;
