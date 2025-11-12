-- Phase 5: Fix resolve_unknown_epc to populate size_ml from p_size
-- Handles inputs like '750ml', '375 ML', '1L', '1.75L', or plain digits

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
  v_size_ml integer;
  v_size_clean text;
begin
  -- Enforce that caller belongs to the organization
  select organization_id into v_profile_org
  from public.profiles
  where id = auth.uid();

  if v_profile_org is null or v_profile_org <> p_organization_id then
    raise exception 'not authorized for organization';
  end if;

  -- Derive size_ml from p_size if possible
  v_size_ml := null;
  if p_size is not null then
    v_size_clean := trim(lower(p_size));
    -- If ends with 'ml' or contains ml, strip non-digits and cast
    if v_size_clean ~ 'ml$' or v_size_clean like '%ml%' then
      v_size_ml := nullif(regexp_replace(v_size_clean, '[^0-9]', '', 'g'), '')::int;
    -- If ends with 'l' (liters), convert to ml (supports decimals like 1.75L)
    elsif v_size_clean ~ 'l$' or v_size_clean like '%l' then
      v_size_ml := (nullif(regexp_replace(v_size_clean, '[^0-9\.]', '', 'g'), '')::numeric * 1000)::int;
    -- If just digits assume ml
    elsif v_size_clean ~ '^[0-9]+$' then
      v_size_ml := v_size_clean::int;
    end if;
  end if;

  -- Create bottle (fails if already exists due to unique constraint)
  insert into public.bottles (
    organization_id, rfid_tag, brand, product, type, size, size_ml, retail_price, status, location_id, last_scanned
  ) values (
    p_organization_id, p_rfid_tag, p_brand, p_product, p_type, p_size, v_size_ml, p_price, p_status, p_location_id, now()
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
      'size_ml', v_size_ml,
      'price', p_price,
      'status', p_status
    )
  );

  return v_bottle_id;
end
$$;


