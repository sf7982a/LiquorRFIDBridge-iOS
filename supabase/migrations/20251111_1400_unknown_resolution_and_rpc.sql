-- Reconciliation support: link unknown EPCs to created bottles atomically

-- Add resolution fields on unknown_epcs
alter table public.unknown_epcs
  add column if not exists linked_bottle_id uuid references public.bottles(id),
  add column if not exists resolved_at timestamptz,
  add column if not exists resolved_by uuid references public.profiles(id);

create index if not exists idx_unknown_org_resolved
  on public.unknown_epcs (organization_id, resolved_at nulls first);

-- Ensure bottles has membership RLS policies for admin REST access
alter table public.bottles enable row level security;

do $$
begin
  create policy bottles_select
    on public.bottles
    for select
    using (
      exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = bottles.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy bottles_insert
    on public.bottles
    for insert
    with check (
      exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = bottles.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy bottles_update
    on public.bottles
    for update
    using (
      exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = bottles.organization_id
      )
    )
    with check (
      exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = bottles.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy bottles_delete
    on public.bottles
    for delete
    using (
      exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = bottles.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

-- Reconciliation RPC (SECURITY INVOKER; relies on RLS)
create or replace function public.resolve_unknown_epc(
  p_organization_id uuid,
  p_rfid_tag text,
  p_location_id uuid,
  p_brand text,
  p_product text,
  p_type public.bottle_type,
  p_size text,
  p_price numeric(10,2),
  p_status public.bottle_status default 'active',
  p_create_initial_count boolean default true
) returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_profile_org uuid;
  v_bottle_id uuid;
  v_today date := (now() at time zone 'utc')::date;
begin
  -- Enforce that caller belongs to the organization
  select organization_id into v_profile_org
  from public.profiles
  where id = auth.uid();

  if v_profile_org is null or v_profile_org <> p_organization_id then
    raise exception 'not authorized for organization';
  end if;

  -- Create bottle (fails if already exists due to unique constraint)
  insert into public.bottles (
    organization_id, rfid_tag, brand, product, type, size, retail_price, status, location_id, last_scanned
  ) values (
    p_organization_id, p_rfid_tag, p_brand, p_product, p_type, p_size, p_price, p_status, p_location_id, now()
  )
  returning id into v_bottle_id;

  -- Optionally backfill idempotent count for today at location
  if p_create_initial_count then
    insert into public.inventory_counts (
      organization_id, bottle_id, location_id, counted_at, session_id, rssi, metadata
    ) values (
      p_organization_id, v_bottle_id, p_location_id, v_today, null, null, '{}'::jsonb
    )
    on conflict (organization_id, bottle_id, counted_at, location_id) do nothing;
  end if;

  -- Link and mark unknown as resolved
  update public.unknown_epcs
    set linked_bottle_id = v_bottle_id,
        resolved_at = now(),
        resolved_by = auth.uid()
  where organization_id = p_organization_id
    and rfid_tag = p_rfid_tag;

  return v_bottle_id;
end
$$;


