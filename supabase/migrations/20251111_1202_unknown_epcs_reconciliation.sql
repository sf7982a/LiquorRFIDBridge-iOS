-- Add reconciliation fields to unknown_epcs for web resolution
alter table public.unknown_epcs
  add column if not exists brand text,
  add column if not exists product_id uuid references public.product_names(id),
  add column if not exists type text,
  add column if not exists size text,
  add column if not exists price numeric(10,2),
  add column if not exists proposed_status public.bottle_status;

-- Helpful index for product resolution workflows
create index if not exists idx_unknown_org_last_seen
  on public.unknown_epcs (organization_id, last_seen_at desc);


