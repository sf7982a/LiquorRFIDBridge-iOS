# LiquorRFID Admin Web

Web admin UI for reconciliation, bottles admin, and reporting. Built with Next.js + Supabase.

## Auth

- Magic link sign-in at `/auth/sign-in` (Supabase OTP).
- UI role gating via `user_metadata.role` (`admin`, `manager`, `staff`).
- CSV export buttons require `admin` or `manager`.

## Modules

- Reconciliation `/reconciliation`:
  - Lists `unresolved_unknowns` with search and keyset pagination.
  - Resolve drawer calls RPC `resolve_unknown_epc`.
  - Bulk resolve: shared fields + per-row location overrides.

- Admin Bottles `/bottles`:
  - Filters: `status`, `location_id`, `brand`, `type`. Sort `last_scanned desc`.
  - Detail `/bottles/[id]`: edit fields, move location, recent counts, movement journal (create).

- Reporting `/reporting`:
  - Dashboard cards from `dashboard_cards`.
  - Daily counts `/reporting/counts` from `inventory_counts_daily` (CSV from `inventory_counts_daily_export`).
  - Missing today `/reporting/missing` from `inventory_missing_today`.

## REST patterns

Headers:
- `apikey`: anon key
- `Authorization`: `Bearer <user_access_token>`

Key endpoints (examples):
- Unresolved list:
  - `GET /rest/v1/unresolved_unknowns?select=*&order=last_seen_at.desc,id.desc&limit=25`
  - Cursor: `last_seen_at=lte.<ISO>&id=lt.<UUID>`
  - Search: `or=(rfid_tag.ilike.*TERM*,brand.ilike.*TERM*,product_id.eq.UUID)`
- Resolve RPC:
  - `POST /rest/v1/rpc/resolve_unknown_epc` body JSON:
    - `p_rfid_tag`, `p_location_id`, `p_brand`, `p_product`, `p_type`, `p_size`, `p_price`, `p_status`, `p_create_initial_count`
- Bottles:
  - `GET /rest/v1/bottles?...&order=last_scanned.desc,id.desc&limit=25`
- Counts daily:
  - `GET /rest/v1/inventory_counts_daily?...&order=counted_date.desc,id.desc&limit=25`
  - CSV: `GET /rest/v1/inventory_counts_daily_export?select=*` with `Accept: text/csv`
- Dashboard cards:
  - `GET /rest/v1/dashboard_cards?select=*&limit=1`

## Caching keys

Lightweight `sessionStorage` caching reduces refetch on navigation.

- `unresolved:list:{org}:{q}:{pageSize}:{cursor}`
  - `cursor` = `last_seen_at|id` or `start`
  - TTL ~30s
- `bottles:list:{org}:{filters}:{sort}:{pageSize}:{cursor}`
  - `filters` = `s=<status>,l=<location>,b=<brand>,t=<type>`
  - `sort` = `last_scanned_desc`
  - TTL ~30s
- `countsDaily:{org}:{range}:{location}:{facetHash}:{pageSize}:{cursor}`
  - `range` = `YYYY-MM-DD_YYYY-MM-DD`
  - `facetHash` = hash(brand, product, type, size)
  - TTL ~60s
- `dashboard:{org}:v1`
  - TTL ~60s

Notes:
- Organization id is read from `user_metadata.organization_id` or `user_metadata.org`, falling back to `"unknown"`.
- RLS enforces org scope; caching keys are namespaced by org for safety.

## Role matrix (UI intent)

- Admin: resolve, bottles CRUD/move, exports, reports
- Manager: resolve, edit limited fields, move, exports, reports
- Staff: resolve, view bottles + reports, no exports

RLS should enforce org-scoped data access and restrict RPC execution to authenticated roles.

## Development

1. Create `web/.env.local` with:
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
2. Install and run:
   - `npm install`
   - `npm run dev`
3. Navigate to `/auth/sign-in`, then use the app.

## Deployment

- Vercel Environment Variables:
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- Supabase → Authentication → Redirect URLs:
  - Add your production domain (e.g., `https://app.example.com`)
  - Keep local dev: `http://localhost:3000`
- Synthetic checks (CI):
  - Set repo secret `SYNTHETIC_BASE_URL` to your production URL to enable scheduled probes.
    Example: `https://8ball-rfid-system-git-main-sam-fishers-projects-6e9188ff.vercel.app/`

## E2E Testing

- Playwright scaffolding is included. To run against a deployed env:
  - `E2E_BASE_URL="https://8ball-rfid-system-git-main-sam-fishers-projects-6e9188ff.vercel.app/" npx playwright test`
  - Tests are skipped if `E2E_BASE_URL` is not set


