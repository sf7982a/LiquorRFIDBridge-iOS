//
//  Config.swift
//  LiquorRFIDBridge
//
//  Created on 2025-10-11
//  Copyright © 2025 8Ball Inventory System. All rights reserved.
//

import Foundation

/// Central configuration file containing all app constants and credentials
/// for the iOS RFID Bridge App
struct AppConfig {
    
    // MARK: - Supabase Configuration
    
    /// Supabase project URL
    static let supabaseURL = "https://rkczvecusafmebwgsmrb.supabase.co"
    
    /// Anonymous key for public API access
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJrY3p2ZWN1c2FmbWVid2dzbXJiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI5NTY2MDMsImV4cCI6MjA2ODUzMjYwM30.PxVT9RAVH14B9MCmmpXaEzYeUOUqP04AA_LvAATCHcQ"
    
    /// Functions base URL derived from project ref
    static var functionsBaseURL: String {
        // Transform "https://<ref>.supabase.co" -> "https://<ref>.functions.supabase.co"
        supabaseURL.replacingOccurrences(of: ".supabase.co", with: ".functions.supabase.co")
    }
    
    /// App version from Info.plist
       static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    
    // MARK: - Organization
    
    /// Organization UUID for 8Ball Inventory System
    static let organizationId = "7e4c68fd-f6a8-4aa6-97a1-aa38711aafd2"
    
    // MARK: - RFID Reader
    
    /// Zebra RFID reader protocol identifier
    static let readerProtocol = "com.zebra.rfd8X00_easytext"
    
    /// Zebra RFID reader model number
    static let readerModel = "RFD4031-G10B700-US"
    
    /// Time window (in seconds) to filter duplicate tag reads
    static let duplicateFilterWindow: TimeInterval = 2.0
    
    /// Maximum tag read rate (tags per second)
    static let maxReadRate: Int = 1300
    
    // MARK: - Offline Queue Configuration
    
    /// Maximum number of tags to queue when offline
    static let maxQueueSize: Int = 1000
    
    /// Enable/disable uploads (kill switch)
    static let uploadEnabled: Bool = true
    
    /// Maximum batch size per upload (must be <= 100 due to Edge Function limits)
    static let queueBatchSize: Int = 100
    
    /// Interval (seconds) for periodic flush attempts while online
    static let flushIntervalSeconds: TimeInterval = 20.0
    
    /// Base backoff seconds (exponential with jitter)
    static let backoffBaseSeconds: TimeInterval = 2.0
    
    /// Maximum backoff seconds
    static let backoffMaxSeconds: TimeInterval = 60.0
    
    /// Jitter ratio (0.2 = ±20%)
    static let backoffJitterRatio: Double = 0.2
    
    /// Maximum number of retry attempts for failed uploads
    static let maxRetryAttempts: Int = 3
    
    /// Maximum number of upload attempts before giving up on an item
    static let maxUploadAttempts: Int = 8
    
    // MARK: - Session Configuration
    
    /// Default device name for this bridge
    static let deviceName = "iPhone 14 Plus"
    
    /// Whether to auto-generate session names with timestamp
    static let sessionAutoGenerateName: Bool = true
    
    /// Count each EPC only once per active session (app-side de-dup)
    static let countUniquePerSession: Bool = true
    
    /// Optional minimum RSSI threshold to accept a read (e.g., -60)
    /// Set to nil to disable RSSI filtering
    static let minAcceptedRSSI: Int? = nil
    
    // MARK: - Computed Properties
    
    /// Edge Function endpoints
    static var fnCreateSession: String { "\(functionsBaseURL)/create_session" }
    static var fnBatchInsertScans: String { "\(functionsBaseURL)/batch_insert_scans" }
    static var fnCompleteSession: String { "\(functionsBaseURL)/complete_session" }
    static var fnUpsertBottleOnScan: String { "\(functionsBaseURL)/upsert_bottle_on_scan" }
    static var fnScanUpsert: String { "\(functionsBaseURL)/scan-upsert" }

    /// Full REST endpoint for locations table
    static var locationsEndpoint: String {
        "\(supabaseURL)/rest/v1/locations"
    }
    
    /// Standard HTTP headers for Supabase API requests
    static var supabaseHeaders: [String: String] {
        [
            "apikey": supabaseAnonKey,
            "Authorization": "Bearer \(supabaseAnonKey)",
            "Content-Type": "application/json",
            "Prefer": "return=minimal"
        ]
    }
}
