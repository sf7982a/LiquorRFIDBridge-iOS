# LiquorRFIDBridge iOS

An iOS companion app for the 8Ball Inventory System that enables RFID scanning capabilities using Zebra RFD40 handheld readers. This bridge app seamlessly connects physical RFID tag scanning with your web-based inventory management system.

## Overview

LiquorRFIDBridge is a native iOS application that bridges the gap between Zebra RFID handheld scanners and the 8Ball Inventory web application. It enables real-time inventory tracking by scanning RFID tags and syncing data directly to Supabase, making inventory counts accessible instantly in the web interface.

## Business Goals (One‑pager)

- Enable fast, accurate liquor inventory using RFID.
- Input inventory once (on arrival) without duplicates.
- Perform daily inventory audits per location without inflating stock.
- Provide a simple iOS app for scanning and a web app for viewing counts, variances, and movement history.

## Technical Architecture (Current)

- Hardware: Zebra RFD40 Premium Plus via MFi/iAP2 (trigger‑driven scanning supported).
- Mobile: SwiftUI app with Zebra iOS SDK; unique‑tag reporting + app de‑dup; optional RSSI floor.
- Transport: ASCII connection established; operational mode MFi; interface events logged (Bluetooth/USB).
- Backend: Supabase (Postgres + Edge Functions). App uses anon key; writes go through Functions with service role on server.
- Functions (deployed):
  - `create_session`: idempotent upsert of scan session
  - `batch_insert_scans`: idempotent batched tag inserts
  - `complete_session`: update session on stop/complete
- RLS: reads scoped via `get_user_organization_id()` / `get_user_role()`; Edge Functions perform writes.

### Key Features

- **RFID Scanning** - Connect to Zebra RFD40 series RFID readers via Bluetooth
- **Real-time Sync** - Instant data synchronization with Supabase backend
- **Offline Queue** - Continue scanning without internet; syncs when connection restored
- **Location Tracking** - Associate scans with specific inventory locations
- **Session Management** - Organize scans into named sessions for better tracking
- **Duplicate Filtering** - Intelligent filtering prevents duplicate tag reads
- **Network Monitoring** - Visual indicators for connectivity status

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
┌─────────────────┐
│   Web App UI    │
│  (React/Next)   │
└─────────────────┘
```

## Requirements

### Hardware
- iOS device running iOS 14.0+
- Zebra RFD40 RFID Reader (Model: RFD4031-G10B700-US or compatible)
- UHF RFID tags (EPC Gen2 compatible)

### Software
- Xcode 14.0+
- Swift 5.5+
- Zebra RFID SDK Framework

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/sf7982a/LiquorRFIDBridge-iOS.git
cd LiquorRFIDBridge-iOS
```

### 2. Open in Xcode

```bash
open LiquorRFIDBridge.xcodeproj
```

### 3. Configure Settings

Update `LiquorRFIDBridge/Configuration/Config.swift` with your settings:

```swift
struct AppConfig {
    static let supabaseURL = "YOUR_SUPABASE_URL"
    static let supabaseAnonKey = "YOUR_ANON_KEY"
    static let organizationId = "YOUR_ORG_UUID"
}
```

### 4. Build and Run

1. Select your target device or simulator
2. Press `Cmd+R` to build and run

## Project Structure

```
LiquorRFIDBridge/
├── Configuration/
│   └── Config.swift              # App configuration and constants
├── Models/
│   ├── Location.swift            # Location data model
│   ├── RFIDTag.swift             # RFID tag data model
│   └── ScanSession.swift         # Scan session data model
├── Services/
│   ├── RFIDService.swift         # Zebra RFID SDK integration
│   ├── SupabaseService.swift    # Supabase API client
│   ├── LocationService.swift    # Location management
│   ├── QueueService.swift        # Offline queue management
│   └── NetworkMonitor.swift     # Network connectivity monitoring
├── Views/
│   └── HomeView.swift            # Main UI interface
└── LiquorRFIDBridgeApp.swift    # App entry point

ZebraRfidSdkFramework.framework/  # Zebra RFID SDK (vendored)
```

## Usage

### Basic Workflow

1. **Launch App** - Open LiquorRFIDBridge on your iOS device
2. **Connect Reader** - Pair with Zebra RFD40 via Bluetooth
3. **Select Location** - Choose inventory location from dropdown
4. **Start Session** - Begin a new scan session (auto-named with timestamp)
5. **Scan Tags** - Trigger RFID scans using reader button
6. **Monitor Progress** - View real-time scan counts and status
7. **Auto-Sync** - Data syncs automatically to web app

### Offline Mode

- Scans are queued locally when internet is unavailable
- Queue holds up to 1,000 tags
- Automatic sync when connection restored
- Visual indicator shows online/offline status

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
- Hierarchical structure (facility → zone → shelf)

### Proposed (Phase 4+)

- `bottles` (one per EPC)
  - id uuid (pk), organization_id uuid, rfid_tag text unique, product_id, current_location_id uuid, status (in_stock/sold/lost), first_seen_at, last_seen_at
- `inventory_movements`
  - input/output/transfer ledger; lines referencing bottle_id; authoritative stock changes
- `inventory_counts`
  - bottle_id uuid, location_id uuid, counted_at date, session_id uuid, rssi, metadata
  - unique (bottle_id, counted_at, location_id) to avoid double‑counting across days

Counting semantics:
- Input sessions: upsert bottles (net new only) + create movement lines; no duplicate inputs.
- Inventory sessions: record daily counts (no stock change), one row per bottle/location/day.
- Output/transfer: write movement lines and update bottle status/location.

## Configuration Options

Key settings in `Config.swift`:

| Setting | Default | Description |
|---------|---------|-------------|
| `duplicateFilterWindow` | 2.0s | Time window to filter duplicate reads |
| `maxQueueSize` | 1000 | Maximum offline queue size |
| `retryDelay` | 5.0s | Delay between retry attempts |
| `maxRetryAttempts` | 3 | Maximum upload retry attempts |
| `maxReadRate` | 1300/s | Maximum tag read rate |

## Related Projects

- **Web Application** - [8Ball Inventory System](https://github.com/yourusername/liquor-inventory-web) (React/Next.js frontend)
- **Supabase Backend** - Shared database and API layer

## Development

### Building for Release

1. Update version in `Info.plist`
2. Archive the app: `Product > Archive`
3. Distribute via App Store Connect or TestFlight

### Testing

- Test with actual Zebra RFD40 hardware for best results
- Simulator testing is limited (no Bluetooth/RFID capabilities)
- Use test environment Supabase project for development

## Troubleshooting

### Reader Won't Connect
- Ensure Bluetooth is enabled
- Check reader is powered on and in range
- Verify reader model compatibility

### Tags Not Syncing
- Check internet connectivity indicator
- Verify Supabase credentials in Config.swift
- Check console logs for API errors

### Duplicate Tags
- Adjust `duplicateFilterWindow` in Config.swift
- Ensure reader antenna configuration is optimal

## Security Notes

- App uses Supabase anon key; writes are done via Edge Functions with the service role server‑side
- Do not ship service role keys in the app
- Review and test RLS policies regularly

## Roadmap & Phases

- Phase 0 — Stabilize reads (DONE)
  - Trigger‑driven vs continuous; unique‑tag reporting; app de‑dup; RSSI floor toggle
  - UI status, battery, interface type; Settings toggles
- Phase 1 — Secure Supabase integration (DONE)
  - App uses anon key; Edge Functions for writes (idempotent); indexes/RLS verified
- Phase 2 — Offline‑first & batching (NEXT)
  - Disk‑backed queue (SQLite/Core Data), batch sizes (100–500), backoff+jitter, telemetry (queue depth/flush)
- Phase 3 — Locations & session UX
  - Location picker + default; require location on session start; web views by location/session
- Phase 4 — Inventory domain modeling
  - bottles, inventory_movements, inventory_counts (unique per bottle/day/location)
- Phase 5 — Bulk input workflow
  - Target quantity flow; commit as one movement; upsert bottles for new EPCs
- Phase 6 — Web dashboards & realtime
  - Stock by location, discrepancies, exports; optional live session monitor
- Phase 7 — Observability & performance
  - OSLog categories, metrics, reader power/profile tuning, background/foreground handling
- Phase 8 — Testing, CI/CD, rollout
  - Protocol mocks, unit/integration tests, TestFlight, feature flags/rollback

## How to Use This Document in a New Chat

Paste the “Business Goals”, “Technical Architecture”, “Database Schema (Proposed)”, and “Roadmap & Phases” sections to bootstrap context. Then specify which phase to continue with (e.g., “Proceed with Phase 2 persistent offline queue”).

## License

Copyright © 2025 8Ball Inventory System. All rights reserved.

## Support

For issues related to:
- **iOS App** - Open an issue in this repository
- **Web Application** - See main web app repository
- **Zebra Hardware** - Contact Zebra Technologies support

## Acknowledgments

- Built with [Zebra RFID SDK](https://www.zebra.com/us/en/support-downloads/software/developer-tools/rfid-sdk.html)
- Backend powered by [Supabase](https://supabase.com)
