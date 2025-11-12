-- Phase 5: Activity logs and resolve audit

-- Enable pgcrypto for gen_random_uuid (usually enabled on Supabase)
create extension if not exists pgcrypto;

-- Activity logs table
create table if not exists public.activity_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  actor_id uuid not null,
  action text not null,
  subject_type text not null,
  subject_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.activity_logs enable row level security;

-- Membership-based policies
do $$
begin
  create policy activity_logs_select
    on public.activity_logs
    for select
    using (
      exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = activity_logs.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy activity_logs_insert
    on public.activity_logs
    for insert
    with check (
      exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.organization_id = activity_logs.organization_id
      )
    );
exception when duplicate_object then null;
end $$;

-- Ensure org/time index exists (also declared in indexes migration; harmless if duplicated)
create index if not exists idx_activity_logs_org_created
  on public.activity_logs (organization_id, created_at desc, id);

-- Update reconciliation RPC to log resolve action
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
  v_unknown_id uuid;
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

  -- Link and mark unknown as resolved, capture id for audit
  update public.unknown_epcs
    set linked_bottle_id = v_bottle_id,
        resolved_at = now(),
        resolved_by = auth.uid()
  where organization_id = p_organization_id
    and rfid_tag = p_rfid_tag
  returning id into v_unknown_id;

  -- Audit log
  insert into public.activity_logs (
    organization_id, actor_id, action, subject_type, subject_id, metadata
  ) values (
    p_organization_id,
    auth.uid(),
    'resolve_unknown_epc',
    'bottle',
    v_bottle_id,
    jsonb_build_object(
      'rfid_tag', p_rfid_tag,
      'unknown_id', v_unknown_id,
      'location_id', p_location_id,
      'brand', p_brand,
      'product', p_product,
      'type', p_type,
      'size', p_size,
      'price', p_price,
      'status', p_status
    )
  );

  return v_bottle_id;
end
$$;


