-- Set a stable search_path for flagged functions
do $$
declare
  fn record;
begin
  for fn in
    select n.nspname, p.proname, p.oid, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'update_updated_at_column',
        'user_has_permission',
        'get_user_permissions',
        'can_manage_organization',
        'get_organization_limits',
        'handle_user_deletion',
        'handle_new_user',
        'upsert_bottle_on_scan_rpc',
        'get_user_organization_id',
        'get_user_role',
        'enforce_location_org_match',
        'enforce_movement_location_org_match'
      )
  loop
    begin
      execute format(
        'alter function %I.%I(%s) set search_path = pg_catalog, public',
        fn.nspname, fn.proname, fn.args
      );
    exception when others then
      raise notice 'Skipping function % due to error: %', fn.proname, sqlerrm;
    end;
  end loop;
end $$;


