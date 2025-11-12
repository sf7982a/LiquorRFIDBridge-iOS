do $$
begin
  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'inventory_counts'
      and c.conname = 'inventory_counts_idem_unique'
  ) then
    execute 'alter table public.inventory_counts add constraint inventory_counts_idem_unique unique (organization_id, bottle_id, counted_at, location_id)';
  end if;
end $$;

-- Helpful index for reporting
create index if not exists idx_inventory_counts_org_date
  on public.inventory_counts (organization_id, counted_at desc);


