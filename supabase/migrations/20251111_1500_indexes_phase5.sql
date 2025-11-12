-- Phase 5: Indexes & Performance
-- Cover common query paths and paginated sorts

-- bottles: org + sorts/filters
create index if not exists idx_bottles_org_last_scanned
  on public.bottles (organization_id, last_scanned desc, id);

create index if not exists idx_bottles_org_status_last_scanned
  on public.bottles (organization_id, status, last_scanned desc, id);

create index if not exists idx_bottles_org_location_last_scanned
  on public.bottles (organization_id, location_id, last_scanned desc, id);

-- unknown_epcs: unresolved list by last_seen_at
create index if not exists idx_unknown_org_last_seen
  on public.unknown_epcs (organization_id, last_seen_at desc, id);

create index if not exists idx_unknown_org_last_seen_unresolved
  on public.unknown_epcs (organization_id, last_seen_at desc, id)
  where resolved_at is null;

-- inventory_counts: daily reporting by org/date (+location)
create index if not exists idx_counts_org_counted_at
  on public.inventory_counts (organization_id, counted_at desc, id);

create index if not exists idx_counts_org_location_counted_at
  on public.inventory_counts (organization_id, location_id, counted_at desc, bottle_id);

-- activity_logs (forward-declared) fast org/date lookups
create index if not exists idx_activity_logs_org_created
  on public.activity_logs (organization_id, created_at desc, id);


