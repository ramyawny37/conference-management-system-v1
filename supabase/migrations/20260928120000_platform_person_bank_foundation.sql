-- P2A: canonical business identities; no legacy import or client API.
begin;

create function platform_private.person_name_key(p_value text)
returns text language sql immutable parallel safe set search_path='' as $$
  select lower(btrim(regexp_replace(coalesce(p_value,''),'[[:space:]]+',' ','g')));
$$;

create function platform_private.person_phone_key(p_value text)
returns text language sql immutable parallel safe set search_path='' as $$
  select regexp_replace(translate(coalesce(p_value,''),'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789'),'[^0-9]','','g');
$$;

create table platform.people (
  id uuid primary key default extensions.gen_random_uuid(),
  full_name text not null check (char_length(full_name) between 1 and 240 and platform_private.person_name_key(full_name)<>''),
  phone text null check (phone is null or (char_length(phone) between 1 and 40 and platform_private.person_phone_key(phone)<>'')),
  gender text null check (gender in ('male','female')),
  date_of_birth date null,
  church text null check (church is null or (char_length(church)<=200 and platform_private.person_name_key(church)<>'')),
  name_search text generated always as (platform_private.person_name_key(full_name)) stored,
  phone_search text generated always as (platform_private.person_phone_key(phone)) stored,
  revision bigint not null default 1 check (revision>0),
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  -- NULL actors are reserved for trusted system import/bootstrap/reconciliation.
  -- Future exposed mutations must derive actors from authenticated context, never client IDs.
  created_by uuid null references platform.profiles(user_id) on delete restrict,
  updated_by uuid null references platform.profiles(user_id) on delete restrict
);

-- Nonunique search indexes: neither names nor phones establish identity.
create index people_name_search_idx on platform.people (name_search text_pattern_ops);
create index people_phone_search_idx on platform.people (phone_search text_pattern_ops) where phone is not null;
create index people_search_order_idx on platform.people (name_search collate "C",id);
create trigger people_updated_at before update on platform.people
  for each row execute function platform_private.set_updated_at();

-- Internal invoker-only primitive. Future callers must first pass the existing
-- approved-account/device/session dispatcher and canonical permission checks.
-- No exposed RPC, client privileges, permission grants, or mutation path in P2A.
create function platform_private.search_people(p_query text default '',p_gender text default null,p_limit integer default 20)
returns setof platform.people language plpgsql stable security invoker set search_path='' as $$
declare
  v_name text := platform_private.person_name_key(p_query);
  v_phone text := platform_private.person_phone_key(p_query);
  -- Only digits and phone-format characters enable phone lookup; mixed text is name-only.
  v_phone_query boolean := coalesce(p_query,'') ~ '^[0-9٠-٩۰-۹[:space:]+().-]+$' and v_phone<>'';
  v_limit integer := greatest(1,least(coalesce(p_limit,20),50));
  v_pattern text;
begin
  if p_gender is not null and p_gender not in ('male','female') then
    raise exception 'PLATFORM_PERSON_GENDER_INVALID' using errcode='22023';
  end if;
  -- Escape LIKE metacharacters so user text remains literal prefix input.
  v_pattern := replace(replace(replace(v_name,E'\\',E'\\\\'),'%',E'\\%'),'_',E'\\_')||'%';
  return query select p.* from platform.people p
    where (p_gender is null or p.gender=p_gender)
      and (v_name='' or p.name_search like v_pattern escape E'\\'
        or (v_phone_query and p.phone is not null and p.phone_search like v_phone||'%'))
    order by p.name_search collate "C",p.id limit v_limit;
end;
$$;

alter table platform.people enable row level security;
alter table platform.people force row level security;
revoke all on table platform.people from public,anon,authenticated,service_role;
revoke all on function platform_private.person_name_key(text) from public,anon,authenticated,service_role;
revoke all on function platform_private.person_phone_key(text) from public,anon,authenticated,service_role;
revoke all on function platform_private.search_people(text,text,integer) from public,anon,authenticated,service_role;

comment on table platform.people is 'Canonical reusable business Person, distinct from login User. No client API in P2A. Future module references must restrict Person deletion; deleting participation must never delete Person.';
commit;
