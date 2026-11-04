begin;
revoke all on function public.search_reservations_people(uuid,text,integer)
  from public,anon,authenticated;
commit;;
