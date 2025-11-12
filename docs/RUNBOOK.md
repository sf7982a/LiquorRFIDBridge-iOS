# Incident Runbook

This runbook outlines how to diagnose and remediate common production issues.

## Web down / 5xx
- Check Vercel status and recent deploys
- Inspect CI synthetic checks (GitHub Actions → Synthetic Checks)
- Verify `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` env vars on Vercel
- Review Supabase API logs for elevated 5xx and p95 latency (Advisors and Logs)

## Edge Function errors
- Supabase Dashboard → Functions → Logs
- Confirm `verify_jwt = true` and requests include `apikey` and `Authorization: Bearer <token>`
- Look for auth failures; rotate keys if needed
- For hotfix: rollback function to previous version, then redeploy

## Database slow queries / timeouts
- Enable/inspect `pg_stat_statements` in Supabase
- Use Advisors (Performance) to identify missing indexes
- Verify pagination is keyset-based (no large offsets)
- Add/adjust indexes on:
  - `bottles (organization_id, last_scanned desc, id)`
  - `unknown_epcs (organization_id, last_seen_at desc, id)` with partial `resolved_at is null`
  - `inventory_counts (organization_id, counted_at desc, id)`

## RLS / Data leakage concerns
- Confirm cross‑org queries return 0 rows
- Verify policies on: `bottles`, `inventory_counts`, `unknown_epcs`, `inventory_movements`, `activity_logs`
- Re-run RLS tests in CI (Playwright scaffolding and manual checks)

## iOS queue backlog
- In-app telemetry shows: queue depth, last flush success/failure
- Ask user to connect to reliable network; queue flushes automatically
- If items permanently fail (exhausted retries), examine Edge Function logs and payloads

## CSV export failures
- Confirm user role (`user_metadata.role` is `admin` or `manager`)
- Check REST filter correctness and Accept header `text/csv`
- Inspect Supabase logs for 403 or 5xx

## Magic link / Auth redirect issues
- Supabase → Authentication → Redirect URLs includes production + `http://localhost:3000`
- Ensure URL matches exactly (protocol, domain, path if any)


