//
//  LiquorRFIDBridgeApp.swift
//  LiquorRFIDBridge
//
//  Created by Samuel Fisher on 10/11/25.
//

import SwiftUI

@main
struct LiquorRFIDBridgeApp: App {
    
    @StateObject private var rfidService = RFIDService.shared
    @StateObject private var supabaseService = SupabaseService.shared
    @StateObject private var networkMonitor = NetworkMonitor()
    
    init() {
        // Create ONE shared NetworkMonitor instance
        let sharedNetworkMonitor = NetworkMonitor()
        
        // Create queue service with the shared monitor
        let queueService = QueueService(networkMonitor: sharedNetworkMonitor)
        
        // Configure SupabaseService (THIS WAS MISSING!)
        SupabaseService.shared.configure(networkMonitor: sharedNetworkMonitor)
        
        // Configure RFIDService with all dependencies
        RFIDService.shared.configure(
            supabase: SupabaseService.shared,
            queue: queueService,
            network: sharedNetworkMonitor
        )
        
        print("✅ 8Ball RFID Bridge started")
    }
    
    var body: some Scene {
        WindowGroup {
            HomeView()
                .onAppear {
                    // Check Bluetooth permissions
                    checkPermissions()
                }
        }
    }
    
    private func checkPermissions() {
        // Log permission status
        if Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") as? String != nil {
            print("✅ Bluetooth permission configured")
        } else {
            print("⚠️ Bluetooth permission not configured in Info.plist")
        }
    }
}
