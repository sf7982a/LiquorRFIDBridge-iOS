-- Phase 5: CSV-friendly export views
-- PostgREST: add 'Accept: text/csv' to export

-- Unresolved unknowns export (normalized columns)
create or replace view public.unresolved_unknowns_export as
select
  u.organization_id,
  u.rfid_tag,
  u.last_seen_at,
  u.seen_count,
  u.last_location_id,
  coalesce(u.brand, '') as brand_hint,
  u.product_id,
  u.type,
  u.size,
  u.price,
  u.proposed_status
from public.unknown_epcs u
where u.resolved_at is null
order by u.last_seen_at desc;

alter view public.unresolved_unknowns_export set (security_invoker = true);

-- Daily counts export (flattened)
create or replace view public.inventory_counts_daily_export as
select
  d.organization_id,
  d.location_id,
  d.day,
  d.brand,
  d.product,
  d.type,
  d.size,
  d.bottle_count
from public.inventory_counts_daily d
order by d.day desc, d.location_id;

alter view public.inventory_counts_daily_export set (security_invoker = true);


