# LiquorRFIDBridge iOS

> Current Phase: Phase 3 — Locations & session UX

An iOS companion app for the 8Ball Inventory System that enables RFID scanning capabilities with Zebra RFD40 handheld readers and a Supabase backend. The app supports offline‑first queueing and batched uploads to a set of Supabase Edge Functions for secure, idempotent writes.

## Overview

LiquorRFIDBridge is a native iOS application that bridges the gap between Zebra RFID scanners and the 8Ball Inventory web application. It enables real-time inventory tracking by scanning RFID tags and syncing data directly to Supabase, making inventory counts accessible instantly in the web interface.

## Business Goals (One‑pager)

- **Fast, accurate inventory** using RFD40 handheld scanners.
- **Offline‑first + batching** to ensure uninterrupted operations in low connectivity.
- **Location awareness** so every scan is tied to a location and session.
- **Simple UX** for operators; web dashboards for managers.

## Technical Architecture (Current)

- **Hardware**: Zebra RFD40 Premium Plus via MFi/iAP2 (trigger‑driven supported)
- **Mobile**: SwiftUI app using Zebra iOS SDK; unique‑tag reporting; optional RSSI floor; background/foreground aware
- **Transport**: HTTPS to Supabase Functions; device uses the project’s anon key; server‑side writes use Supabase service role
- **Backend**: Supabase (Postgres + Edge Functions)
- **Functions (deployed)**
  - `create_session` — idempotent upsert of a scan session (stores `organization_id`, `location_id`, timestamps)
  - `complete_session` — marks session complete on finish
  - `scan-upsert` (Edge Function) — updates existing `bottles` for known EPCs (sets `location_id`, sets `status = 'active'`, updates `last_scanned`) and upserts to `inventory_counts` keyed by `(organization_id, bottle_id, counted_at)`; unknown EPCs are skipped (not auto‑inserted) and logged to `public.unknown_epcs` for later reconciliation in the web app
- **RLS / constraints**
  - `locations`: `is_active` default `true`, `settings` default `'{}'::jsonb`
  - FKs: `scan_sessions.location_id` and `rfid_scans.location_id` reference `locations(id)` with `ON DELETE SET NULL`
  - Recommend a unique index on `inventory_counts (organization_id, bottle_id, counted_at)` to ensure idempotent counts

### Key Features

- **RFID Scanning** — Connect to Zebra RFD40 via Bluetooth; trigger‑driven scanning
- **Real-time Sync** — Automatic background flush to Supabase
- **Offline Mode** — Disk‑backed queue (SQLite), retries with exponential backoff
- **Location Selection** — Picker + persisted default per device
- **Session Management** — Enforce selecting a location before starting
- **Duplicate Filtering** — App‑side unique tag constraint per session
- **Network Monitoring** — App indicates connectivity and sync status

## Architecture

```
┌─────────────────┐
│  Zebra RFD40    │
│  RFID Reader    │
└────────┬────────┘
         │ Bluetooth
         ▼
┌─────────────────┐
│   iOS Bridge    │
│      App        │
└────────┬────────┘
         │ HTTPS
         ▼
┌─────────────────┐
│    Supabase     │
│    Database     │
└────────┬────────┘
         │
         ▼
┌────────────────┐
│   Web App UI   │
│  (React/Next)  |
└────────────────┘
```

## Requirements

### Hardware
- iOS device running iOS 14.0+
- Zebra RFD40 RFID Reader (Model: RFD4031‑G10B700‑US or compatible)
- UHF RFID tags (EPC Gen2 compatible)

### Software
- Xcode 14.0+
- Swift 5.5+
- Zebra RFID SDK Framework

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/sf7982/LiquorRFIDBridge-iOS.git
cd LiquorRFIDBridge-Ih5EJ
```

### 2. Open in Xcode

```bash
open LiquorRFIDBridge.xcodeproj
```

### 3. Configure Settings

Update `LiquorRFIDBridge/Configuration/Config.swift` with your values:

```swift
struct AppConfig {
    static let supabaseURL = "YOUR_SUPABASE_URL"
    static let supabaseAnonKey = "YOUR_ANON_KEY"
    static let organizationId = "YOUR_ORG_UUID"
    // Tuning knobs for offline/batching
    static let maxQueueSize: Int = 1000
    static let queueBatchSize: Int = 100
    static let flushIntervalSeconds: TimeInterval = 20.0
    static let backoffBaseSeconds: TimeInterval = 2.0
    static let backoffMaxSeconds: TimeInterval = 60.0
}
```

### 4. Build and Run

1. Select your target device or simulator
2. `Cmd+R` to build & run

## Project Structure

```
LiquorRFIDBridge/
├── Configuration/
│   └── Config.swift              # App configuration and constants
├── LiquorRFIDBridge/
│   ├── Models/
│   │   ├── Location.swift        # Location model
│   │   ├── RFIDTag.swift         # Tag model
│   │   └── ScanSession.swift     # Session model
│   ├── Services/
│   │   ├── RFIDService.swift     # Zebra SDK integration + session orchestration
│   │  ├─┬ SupabaseService.swift # Client for Supabase & Functions
│   │  ├─┬ LocationService.swift  # Fetch/cache locations; default selection; refresh
│   │  ├─┬ QueueService.swift     # Disk-backed queue + backoff + flush scheduling
│   │  └── PersistentQueue.swift  # SQLite queue storage
│   ├── Views/
│   │   └── HomeView.swift        # Main UI (status, location picker, start/stop)
│   └── LiquorRFIDBridgeApp.swift # App root
├── supabase/
│   └── functions/
│       ├── create_session/
│       ├── complete_session/
│       ├── batch_insert_scans/
│       └── upsert_bottle_on_scan/   # Legacy; app now calls `scan-upsert` (Edge)
│
│   # Note: `scan-upsert` is deployed as an Edge Function and may not be present here.
└── ZebraRfidSdkFramework.framework/
```

## Usage

### Basic Workflow

1. **Launch App** — Open LiquorRFIDBridge on your iOS device
2. **Connect Reader** — Pair with Zebra RFD40 via Bluetooth (MFi)
3. **Select Location** — Choose inventory location from the picker (required)
4. **Start Session** — Creates a `scan_session` row via `create_session`
5. **Scan Tags** — Trigger on the RFD40; app dedupes, queues, and uploads batches in background to `scan-upsert`
6. **Monitor** — Queue depth, last flush success/failure, and counts update live in the UI

### Offline Mode

- **Resilient queue** — Local SQLite circular buffer (default `maxQueueSize = 1000`)
- **Backoff & retry** — Configurable `backoffBaseSeconds`/`backoffMaxSeconds`
- **Pause/Resume** — Flush pauses on background, resumes on foreground

### Supabase Function (scan‑upsert) — Test via cURL

Ensure the `scan-upsert` Edge Function has **Verify JWT disabled** (Supabase → Project → Functions → `scan-upsert` → Settings → toggle off). Then test with:

```bash
# Set your values
export SUPABASE_URL='https://<your-project>.supabase.co'
export ORG_ID='00000000-0000-0000-0000-000000000000'
export LOC_ID='00000000-0000-0000-0000-000000000000'
export SESSION_ID='00000000-0000-0000-0000-000000000000'

curl -s -X POST "$SUPABASE_URL/functions/v1/scan-upsert" \
  -H "Content-Type: application/json" \
  # -H "apikey: $SUPABASE_ANON_KEY" \  # optional when Verify JWT is disabled
  -d "{\"organization_id\": \"$ORG_ID\", \"location_id\": \"$LOC_ID\", \"session_id\": \"$SESSION_ID\", \"session_type\": \"inventory\", \"tags\": [{ \"rfid_tag\": \"E280...\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"rssi\": -45 }] }"
```

Notes:
- Do not send an `Authorization` header when Verify JWT is disabled; otherwise you may see “Invalid JWT”.
- The app should call `scan-upsert` (not the legacy `upsert_bottle_on_scan`).

Expected response:

```json
{
  "success": true,
  "updated_bottles": 1,
  "counts_inserted": 1,
  "skipped_new_epcs": []
}
```

## Database Schema

The app currently interacts with these Supabase tables:

### `scan_sessions`
- Tracks individual scanning sessions
- Links to organization and device
- Stores session metadata (start/end times, location)

### `rfid_scans`
- Individual RFID tag reads
- Associated with session and location
- Includes EPC, timestamp, signal strength

### `locations`
- Inventory locations within organization
- Hierarchical (e.g., venue → area → shelf)
- `is_active` default `true`, `settings` default `'{}'::jsonb`

### Planned (Phase 4+)
- `bottles` (one per EPC)
  - `id` (uuid, pk), `organization_id`, `rfid_code`/`product_id`, `status` (e.g., `in_stock`/`sold`), `first_seen_at`, `last_scanned`, etc.
- `inventory_movements` (ledger)
- `inventory_counts` (unique per `organization_id + bottle_id + counted_at`)

> Note: ensure foreign keys from `scan_sessions.location_id` and `rfid_scans.location_id` to `locations(id)` with `ON DELETE SET NULL`. Create a unique index on `inventory_counts(organization_id, bottle_id, counted_at)` for idempotent counts.

## Configuration Options

Key settings in `Config.swift`:

| Setting                 | Default | Description                                 |
|-------------------------|---------|---------------------------------------------|
| `duplicateFilterWindow` | 2.0s    | De-duplication window for rapid tag reads   |
| `maxQueueSize`          | 1000    | Max queued tags for offline buffer          |
| `queueBatchSize`        | 100     | Batch size per flush                        |
| `flushIntervalSeconds`  | 20.0    | Background flush interval                   |
| `backoffBaseSeconds`    | 2.0     | Base for exponential backoff on failures    |
| `backoffMaxSeconds`     | 60.0    | Max backoff cap in seconds                  |

## Roadmap & Phases

- **Phase 0 — Stabilize reads (DONE)**
  - Trigger‑driven vs. continuous; unique‑tag reporting; RSSI threshold
  - UI status, battery, interface type; settings toggles
- **Phase 1 — Secure Supabase integration (DONE)**
  - App uses anon key; writes via Edge Functions (service role); RLS policies validated
- **Phase 2 — Offline‑first & batching (DONE)**
  - Disk‑backed queue, batched uploads, exponential backoff, queue telemetry
  - Background/foreground awareness (pause/resume flush)
- **Phase 3 — Locations & session UX (IN PROGRESS)**
  - ✅ Server‑side: `locations` constraints & indexes (FKs + defaults)
  - ✅ Location picker UI & persisted default
  - ✅ Enforce “select location before start”
  - ✅ `scan-upsert` RPC for updating known `bottles` and inserting `inventory_counts`
  - ✅ Pre‑session scanning guard (ignore scans before session)
  - 🔄 Continue polishing UX, error handling, and empty states
- **Phase 4 — Inventory domain modeling**
  - `bottles`, `inventory_movements`, `inventory_counts` schema finalization & UI
- **Phase 5 — Bulk input workflow**
  - Target quantity flow; idempotent bulk upserts for new items
- **Phase 6 — Web dashboards & realtime**
  - Live view by location/session; managerial insights
- **Phase 7 — Observability & rollout**
  - Telemetry dashboards, alerts, TestFlight, production hardening

## Next Chat: Context & Open Items

- `scan-upsert` RPC is now update‑only (no auto‑insert) to respect `bottles` NOT NULL fields (e.g., `brand`). It updates existing bottles and writes `inventory_counts` for known EPCs; unknown EPCs are returned via `skipped_new_epcs` and recorded in `public.unknown_epcs` for later reconciliation by the web app.
- iOS app updated to call `AppConfig.fnScanUpsert` (points to `/functions/v1/scan-upsert`) and to display queue telemetry + enforce location selection before starting a session. Phase 2 is complete; Phase 3 is in progress.
- Supabase side:
  - `scan-upsert` function deployed with **Verify JWT disabled** (required for anon-key client calls). Ensure `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` env vars are set for the function and re‑deploy after changes.
  - Do not send an `Authorization` header for this function; if included you may see “Invalid JWT”.
  - Ensure a unique index on `inventory_counts (organization_id, bottle_id, counted_at)` to enable idempotent counts.
  - `locations` table has `is_active` default `true` and `settings` default `'{}'::jsonb`; `scan_sessions.location_id` and `rfid_scans.location_id` enforce FK to `locations(id)` with `ON DELETE SET NULL`.
- **Open decisions**
  - Whether to auto‑create `bottles` for unknown EPCs in `scan-upsert`. If yes, specify which NOT NULL fields and defaults to populate (`brand`, `product_id`, etc.) so we can safely insert and begin counting immediately.
  - Confirm the exact unique key for `public.inventory_counts` to use with `upsert` (currently assuming `(organization_id, bottle_id, counted_at)`).
  - Verify Xcode is opened from `/Users/samuelfisher/.cursor/worktrees/LiquorRFIDBridge/Ih5EJ/LiquorRFIDBridge.xcodeproj` so code edits sync between Cursor/Xcode.

## Support

- **iOS App** — Open an issue in this repository
- **Web App** — See main 8Ball web repo
- **Zebra Hardware** — Contact Zebra support

## What's new (Phase 3 wrap‑up)

- Edge Functions
  - Added and deployed `scan-upsert` (alias of `upsert_bottle_on_scan`) with verify_jwt = true
  - Behavior: updates known bottles (location/status/last_scanned), writes daily `inventory_counts`; logs unknown EPCs with counters
- iOS App
  - Enforces selecting a location before starting a session
  - Ignores reads until a session is active
  - Location list cached; default location persisted in preferences
  - Offline queue/backoff tuning exposed in `AppConfig`
- Backend
  - Migration adds counters/timestamps to `public.unknown_epcs` (seen_count, first_seen_at, last_seen_at, last_location_id)
  - Confirmed counts written only for known bottles; unknown EPCs are triaged via `unknown_epcs`

### Function tests (verify_jwt = true)

If your Edge Functions have Verify JWT enabled (recommended for production), include the anon key:

```bash
export SUPABASE_URL='https://<your-project>.supabase.co'
export SUPABASE_ANON_KEY='<your-anon-key>'
export ORG_ID='...' LOC_ID='...' SESSION_ID='...'

curl -s -X POST "$SUPABASE_URL/functions/v1/scan-upsert" \
  -H "Content-Type: application/json" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -d "{\"organization_id\":\"$ORG_ID\",\"location_id\":\"$LOC_ID\",\"session_id\":\"$SESSION_ID\",\"session_type\":\"inventory\",\"tags\":[{\"rfid_tag\":\"E280...\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"rssi\":-45}]}"
```

Notes:
- Counts are created only for EPCs that exist in `public.bottles` for the same `organization_id`
- Unknown tags are upserted into `public.unknown_epcs` and will not produce counts until resolved

## Next Phase (high-level)

- Bottle/Product modeling
  - Web: unknown EPC reconciliation UI, resolve to product/bottle with required fields (brand, type, size, tier, price)
  - DB: finalize NOT NULLs/defaults for `bottles` and related reference data
- Reporting
  - Views for daily counts by location and by product
  - Optional: materialized views for top-line dashboards
- Security/Policies
  - Membership-based RLS for direct REST (if/when needed)
  - Keep mobile read/writes via Edge Functions with verify_jwt enabled
