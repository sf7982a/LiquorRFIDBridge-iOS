# Operations Guide

## Dashboards
- Supabase Advisors (Security & Performance): review weekly, fix high/critical
- Logs: Functions/API error rate and latency percentiles
- DB: `pg_stat_statements` top slow queries
- Web: Vercel Analytics p95 TTFB for list routes
- iOS: Queue telemetry via app logs (depth, success/failure, backoff)

## Alerts
- CI Synthetic Checks failing (GitHub → Actions → Notifications)
- Supabase Logs: consider Logflare/Axiom drains for 5xx rate and latency spikes
- Unknown EPCs surge: threshold alert on unresolved count growth (cron + SQL)

## Production URL
- Web App: https://8ball-rfid-system-git-main-sam-fishers-projects-6e9188ff.vercel.app/

## Release Flow
- iOS: Ship via TestFlight; monitor crashes (Xcode Organizer or Crashlytics)
- Web: Deploy via Vercel; preview deployments tied to PRs
- Supabase: Apply migrations via CLI; validate Advisors post-deploy

## Security
- Edge Functions: `verify_jwt = true` in production
- RPC permissions: grant `EXECUTE` only to `authenticated` (revoke `anon`)
- RLS: Organization-scoped policies across all primary tables


