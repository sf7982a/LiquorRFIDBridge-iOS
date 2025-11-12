-- Enable RLS and membership-based policies on rfid_scans and inventory_movements

alter table public.rfid_scans enable row level security;
alter table public.inventory_movements enable row level security;

-- rfid_scans
do $$
begin
  create policy rfid_scans_select
    on public.rfid_scans
    for select
    using (
      exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = rfid_scans.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy rfid_scans_insert
    on public.rfid_scans
    for insert
    with check (
      exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = rfid_scans.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy rfid_scans_update
    on public.rfid_scans
    for update
    using (
      exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = rfid_scans.organization_id
      )
    )
    with check (
      exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = rfid_scans.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy rfid_scans_delete
    on public.rfid_scans
    for delete
    using (
      exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = rfid_scans.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

-- inventory_movements
do $$
begin
  create policy inventory_movements_select
    on public.inventory_movements
    for select
    using (
      exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = inventory_movements.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy inventory_movements_insert
    on public.inventory_movements
    for insert
    with check (
      exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = inventory_movements.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy inventory_movements_update
    on public.inventory_movements
    for update
    using (
      exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = inventory_movements.organization_id
      )
    )
    with check (
      exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = inventory_movements.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy inventory_movements_delete
    on public.inventory_movements
    for delete
    using (
      exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = inventory_movements.organization_id
      )
    );
exception when duplicate_object then null;
end $$;


