-- Restrict RPC EXECUTE to authenticated users only
-- Revoke from anon/public, grant to authenticated
do $$
begin
  revoke all on function public.resolve_unknown_epc(
    uuid, text, uuid, text, text, public.bottle_type, text, numeric, public.bottle_status, boolean
  ) from public;
exception when undefined_function then null;
end $$;

do $$
begin
  revoke all on function public.resolve_unknown_epc(
    uuid, text, uuid, text, text, public.bottle_type, text, numeric, public.bottle_status, boolean
  ) from anon;
exception when undefined_function then null;
end $$;

do $$
begin
  grant execute on function public.resolve_unknown_epc(
    uuid, text, uuid, text, text, public.bottle_type, text, numeric, public.bottle_status, boolean
  ) to authenticated;
exception when undefined_function then null;
end $$;


