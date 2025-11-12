-- Switch flagged views to SECURITY INVOKER to avoid bypassing RLS
do $$
begin
  begin
    execute 'alter view public.brand_tier_distribution set (security_invoker = true)';
  exception when undefined_table then
    raise notice 'View public.brand_tier_distribution not found, skipping';
  end;

  begin
    execute 'alter view public.role_permission_summary set (security_invoker = true)';
  exception when undefined_table then
    raise notice 'View public.role_permission_summary not found, skipping';
  end;

  begin
    execute 'alter view public.tier_inventory_stats set (security_invoker = true)';
  exception when undefined_table then
    raise notice 'View public.tier_inventory_stats not found, skipping';
  end;
end $$;


