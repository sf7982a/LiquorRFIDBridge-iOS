-- View for unresolved unknown EPCs (security invoker; underlying RLS applies)
create or replace view public.unresolved_unknowns as
select
  u.id,
  u.organization_id,
  u.rfid_tag,
  u.last_seen_at,
  u.seen_count,
  u.last_location_id,
  u.brand,
  u.product_id,
  u.type,
  u.size,
  u.price,
  u.proposed_status
from public.unknown_epcs u
where u.resolved_at is null
order by u.last_seen_at desc;

alter view public.unresolved_unknowns set (security_invoker = true);


