-- Enable and define membership-based RLS for REST access

-- inventory_counts
alter table public.inventory_counts enable row level security;

do $$
begin
  -- SELECT
  create policy inv_counts_select
    on public.inventory_counts
    for select
    using (
      exists (
        select 1
        from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = inventory_counts.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  -- INSERT
  create policy inv_counts_insert
    on public.inventory_counts
    for insert
    with check (
      exists (
        select 1
        from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = inventory_counts.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  -- UPDATE
  create policy inv_counts_update
    on public.inventory_counts
    for update
    using (
      exists (
        select 1
        from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = inventory_counts.organization_id
      )
    )
    with check (
      exists (
        select 1
        from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = inventory_counts.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  -- DELETE
  create policy inv_counts_delete
    on public.inventory_counts
    for delete
    using (
      exists (
        select 1
        from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = inventory_counts.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

-- unknown_epcs
alter table public.unknown_epcs enable row level security;

do $$
begin
  create policy unknown_epcs_select
    on public.unknown_epcs
    for select
    using (
      exists (
        select 1
        from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = unknown_epcs.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy unknown_epcs_insert
    on public.unknown_epcs
    for insert
    with check (
      exists (
        select 1
        from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = unknown_epcs.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy unknown_epcs_update
    on public.unknown_epcs
    for update
    using (
      exists (
        select 1
        from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = unknown_epcs.organization_id
      )
    )
    with check (
      exists (
        select 1
        from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = unknown_epcs.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy unknown_epcs_delete
    on public.unknown_epcs
    for delete
    using (
      exists (
        select 1
        from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = unknown_epcs.organization_id
      )
    );
exception when duplicate_object then null;
end $$;


