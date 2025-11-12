-- Add counters and timestamps for unknown EPCs, and supporting indexes
create table if not exists public.unknown_epcs (
  id bigserial primary key,
  organization_id uuid not null,
  rfid_tag text not null,
  location_id uuid not null,
  last_seen_at timestamptz not null default now(),
  unique (organization_id, rfid_tag)
);

alter table public.unknown_epcs
  add column if not exists seen_count integer not null default 1,
  add column if not exists first_seen_at timestamptz not null default now(),
  add column if not exists last_location_id uuid;

-- Ensure the unique constraint exists (PG14+ supports IF NOT EXISTS)
alter table public.unknown_epcs
  add constraint if not exists unknown_epcs_org_tag_key unique (organization_id, rfid_tag);

-- Useful index for dashboards
create index if not exists idx_unknown_org_last_seen
  on public.unknown_epcs (organization_id, last_seen_at desc);


