-- Enforce bottles uniqueness per organization and rfid_tag; align price precision
do $$
begin
  -- Drop any existing unique constraint on rfid_tag alone if present
  if exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'bottles'
      and c.contype = 'u'
      and c.conkey = array[
        (select attnum from pg_attribute where attrelid = t.oid and attname = 'rfid_tag')
      ]
  ) then
    execute (
      select 'alter table public.bottles drop constraint ' || quote_ident(c.conname)
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
      where n.nspname = 'public'
        and t.relname = 'bottles'
        and c.contype = 'u'
        and c.conkey = array[
          (select attnum from pg_attribute where attrelid = t.oid and attname = 'rfid_tag')
        ]
      limit 1
    );
  end if;
exception
  when others then
    raise notice 'Skipping drop of existing unique on bottles.rfid_tag: %', sqlerrm;
end $$;

-- Add composite uniqueness by organization
do $$
begin
  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'bottles'
      and c.conname = 'bottles_org_tag_unique'
  ) then
    execute 'alter table public.bottles add constraint bottles_org_tag_unique unique (organization_id, rfid_tag)';
  end if;
end $$;

-- Helpful indexes
create index if not exists idx_bottles_org_location
  on public.bottles (organization_id, location_id);

create index if not exists idx_bottles_last_scanned
  on public.bottles (organization_id, last_scanned desc);


