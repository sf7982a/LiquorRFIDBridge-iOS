-- Phase 5: Reporting Views (security invoker)
-- Use auth.uid() scoping via CTE to keep index-friendly org filters

-- Daily inventory counts grouped by location/product facets
create or replace view public.inventory_counts_daily as
with me as (
  select organization_id from public.profiles where id = auth.uid()
)
select
  ic.organization_id,
  ic.location_id,
  date(ic.counted_at) as day,
  b.brand,
  b.product,
  b.type,
  b.size,
  count(distinct ic.bottle_id) as bottle_count
from public.inventory_counts ic
join public.bottles b
  on b.id = ic.bottle_id
  and b.organization_id = ic.organization_id
where exists (select 1 from me m where m.organization_id = ic.organization_id)
group by ic.organization_id, ic.location_id, date(ic.counted_at), b.brand, b.product, b.type, b.size
order by day desc;

alter view public.inventory_counts_daily set (security_invoker = true);

-- Bottles missing today (active bottles not counted on current UTC date)
create or replace view public.inventory_missing_today as
with me as (
  select organization_id from public.profiles where id = auth.uid()
),
today as (
  select (now() at time zone 'utc')::date as d
)
select
  b.organization_id,
  b.id as bottle_id,
  b.rfid_tag,
  b.brand,
  b.product,
  b.type,
  b.size,
  b.location_id,
  b.last_scanned
from public.bottles b
cross join today t
where b.status = 'active'
  and exists (select 1 from me m where m.organization_id = b.organization_id)
  and not exists (
    select 1 from public.inventory_counts ic
    where ic.organization_id = b.organization_id
      and ic.bottle_id = b.id
      and date(ic.counted_at) = t.d
  )
order by b.last_scanned nulls last;

alter view public.inventory_missing_today set (security_invoker = true);

-- Dashboard cards: active bottles, unresolved unknowns (24h), today's counts
create or replace view public.dashboard_cards as
with me as (
  select organization_id from public.profiles where id = auth.uid()
),
active_bottles as (
  select b.organization_id, count(*)::bigint as active_bottles
  from public.bottles b
  where b.status = 'active'
    and exists (select 1 from me m where m.organization_id = b.organization_id)
  group by b.organization_id
),
unknown_24h as (
  select u.organization_id, count(*)::bigint as unknown_last_24h
  from public.unknown_epcs u
  where u.resolved_at is null
    and u.last_seen_at > now() - interval '24 hours'
    and exists (select 1 from me m where m.organization_id = u.organization_id)
  group by u.organization_id
),
todays_counts as (
  select ic.organization_id, count(*)::bigint as todays_counts
  from public.inventory_counts ic
  where date(ic.counted_at) = (now() at time zone 'utc')::date
    and exists (select 1 from me m where m.organization_id = ic.organization_id)
  group by ic.organization_id
)
select
  coalesce(a.organization_id, u.organization_id, t.organization_id) as organization_id,
  coalesce(a.active_bottles, 0) as active_bottles,
  coalesce(u.unknown_last_24h, 0) as unknown_last_24h,
  coalesce(t.todays_counts, 0) as todays_counts
from active_bottles a
full outer join unknown_24h u on u.organization_id = a.organization_id
full outer join todays_counts t on t.organization_id = coalesce(a.organization_id, u.organization_id);

alter view public.dashboard_cards set (security_invoker = true);


