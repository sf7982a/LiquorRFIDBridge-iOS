//
//  LiquorRFIDBridgeApp.swift
//  LiquorRFIDBridge
//
//  Created by Samuel Fisher on 10/11/25.
//

import SwiftUI
import ExternalAccessory

@main
struct LiquorRFIDBridgeApp: App {
    
    // Shared singletons — created once and injected
    @StateObject private var rfidService = RFIDService.shared
    @StateObject private var supabaseService = SupabaseService.shared
    @StateObject private var networkMonitor: NetworkMonitor
    @StateObject private var queueService: QueueService
    @StateObject private var locationService = LocationService.shared
    
    init() {
        // Create ONE shared NetworkMonitor and QueueService
        let sharedNetworkMonitor = NetworkMonitor()
        _networkMonitor = StateObject(wrappedValue: sharedNetworkMonitor)
        let createdQueueService = QueueService(networkMonitor: sharedNetworkMonitor)
        _queueService = StateObject(wrappedValue: createdQueueService)
        
        // Configure Supabase with network monitor
        SupabaseService.shared.configure(networkMonitor: sharedNetworkMonitor)
        
        // Inject dependencies into RFIDService
        RFIDService.shared.configure(
            supabase: SupabaseService.shared,
            queue: createdQueueService,
            network: sharedNetworkMonitor
        )
        
        print("8Ball RFID Bridge started")
    }
    
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(rfidService)
                .environmentObject(supabaseService)
                .environmentObject(networkMonitor)
                .environmentObject(queueService)
                .environmentObject(locationService)
                .onAppear {
                    checkPermissions()
                    logConnectedAccessories()
                    // Optional: Auto-start connection on launch
                    // rfidService.connectToReader()
                    Task {
                        await locationService.fetchLocations()
                    }
                }
        }
    }
    
    private func checkPermissions() {
        if Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") as? String != nil {
            print("Bluetooth permission configured")
        } else {
            print("WARNING: Bluetooth permission missing in Info.plist!")
        }
    }

    private func logConnectedAccessories() {
        let accessories = EAAccessoryManager.shared().connectedAccessories
        if accessories.isEmpty {
            print("No connected External Accessories detected")
            return
        }
        for acc in accessories {
            print("Accessory: \(acc.name) | Manufacturer: \(acc.manufacturer) | Model: \(acc.modelNumber)")
            print("  Protocols: \(acc.protocolStrings.joined(separator: ", "))")
        }
    }
}
