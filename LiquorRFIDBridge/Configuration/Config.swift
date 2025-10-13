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
    
    /// Service role key for privileged operations (private for security)
    private static let supabaseServiceKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJrY3p2ZWN1c2FmbWVid2dzbXJiIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1Mjk1NjYwMywiZXhwIjoyMDY4NTMyNjAzfQ.o9Fzb8nbFDI6HiKIXJ6OnhbJ0XyQ7FOwNTn52skJ7hQ"
    
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
    
    /// Delay (in seconds) between retry attempts
    static let retryDelay: TimeInterval = 5.0
    
    /// Maximum number of retry attempts for failed uploads
    static let maxRetryAttempts: Int = 3
    
    // MARK: - Session Configuration
    
    /// Default device name for this bridge
    static let deviceName = "iPhone 14 Plus"
    
    /// Whether to auto-generate session names with timestamp
    static let sessionAutoGenerateName: Bool = true
    
    // MARK: - Computed Properties
    
    /// Full REST endpoint for scan_sessions table
    static var scanSessionsEndpoint: String {
        "\(supabaseURL)/rest/v1/scan_sessions"
    }
    
    /// Full REST endpoint for rfid_scans table
    static var rfidScansEndpoint: String {
        "\(supabaseURL)/rest/v1/rfid_scans"
    }
    
    /// Full REST endpoint for locations table
    static var locationsEndpoint: String {
        "\(supabaseURL)/rest/v1/locations"
    }
    
    /// Standard HTTP headers for Supabase API requests
    static var supabaseHeaders: [String: String] {
        [
            "apikey": supabaseServiceKey,
            "Authorization": "Bearer \(supabaseServiceKey)",
            "Content-Type": "application/json",
            "Prefer": "return=minimal"
        ]
    }
}
