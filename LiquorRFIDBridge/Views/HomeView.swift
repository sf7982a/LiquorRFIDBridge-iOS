//
//  HomeView.swift
//  LiquorRFIDBridge
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var rfidService: RFIDService
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @EnvironmentObject var queueService: QueueService
    @EnvironmentObject var locationService: LocationService
    @State private var selectedSessionType: ScanSession.SessionType = .inventory
    @State private var showingSettings = false
    @State private var selectedLocationId: String? = AppPreferences.shared.defaultLocationId
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // MARK: - Connection Status Card
                    VStack(spacing: 12) {
                        HStack {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 14, height: 14)
                            
                            Text(rfidService.connectionState.rawValue)
                                .font(.headline)
                            
                            Spacer()
                            
                            if rfidService.isConnected {
                                HStack(spacing: 4) {
                                    Image(systemName: batteryIcon)
                                        .foregroundColor(batteryColor)
                                    Text("\(rfidService.batteryLevel)%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        if rfidService.isConnected {
                            Text("Interface: \(rfidService.interfaceDescription)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        // Show error message if present
                        if let error = rfidService.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                        
                        // Show connection state details
                        if rfidService.connectionState == .validating {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Verifying connection...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding()
                    .background(Color(uiColor: .systemGray6))
                    .cornerRadius(12)
                    
                    // MARK: - Queue Telemetry (minimal)
                    if !networkMonitor.isConnected || queueService.queueDepth > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "externaldrive.badge.timemachine")
                                .foregroundColor(.secondary)
                            Text("\(queueService.queueDepth) queued")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let lastFlush = queueService.lastFlushAt {
                                Text("· Last sync \(timeAgo(lastFlush))")
                                    .font(.caption)
                                    .foregroundColor(syncColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if queueService.permanentFailureCount > 0 {
                            Text("⚠️ \(queueService.permanentFailureCount) scans failed permanently")
                                .font(.caption2)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    // MARK: - Location Picker
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Location")
                                .font(.headline)
                            Spacer()
                            if let fetchedAt = locationService.lastFetchedAt {
                                Text("Updated \(timeAgo(fetchedAt))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if locationService.isLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Button {
                                    Task { await locationService.refresh() }
                                } label: {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Refresh Locations")
                            }
                        }
                        
                        // Warn if saved default is missing/inactive
                        if let savedId = AppPreferences.shared.defaultLocationId,
                           !locationService.activeLocations.contains(where: { $0.id == savedId }) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Saved default location is unavailable. Please reselect.")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                Button {
                                    AppPreferences.shared.defaultLocationId = nil
                                    selectedLocationId = nil
                                } label: {
                                    Text("Clear default")
                                }
                                .font(.caption)
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        if !locationService.activeLocations.isEmpty {
                            Picker("Select Location", selection: Binding(
                                get: { selectedLocationId ?? "" },
                                set: { newVal in
                                    selectedLocationId = newVal.isEmpty ? nil : newVal
                                    AppPreferences.shared.defaultLocationId = selectedLocationId
                                }
                            )) {
                                Text("None").tag("")
                                ForEach(locationService.activeLocations, id: \.id) { loc in
                                    Text(loc.displayName).tag(loc.id)
                                }
                            }
                            .pickerStyle(.menu)
                        } else if let err = locationService.errorMessage {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(err)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                Button {
                                    Task { await locationService.refresh() }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Retry")
                                    }
                                }
                                .font(.caption)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No locations available")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Check connectivity, then tap Refresh.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onAppear {
                        // Initialize selection from preferences if it still exists
                        if let pref = AppPreferences.shared.defaultLocationId,
                           locationService.activeLocations.contains(where: { $0.id == pref }) {
                            selectedLocationId = pref
                        }
                    }
                    .padding()
                    .background(Color(uiColor: .systemGray6))
                    .cornerRadius(12)
                    
                    // MARK: - Connection Actions
                    
                    // Connect Button (only show when disconnected)
                    if rfidService.connectionState == .disconnected {
                        Button {
                            rfidService.connectToReader()
                        } label: {
                            HStack {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                Text("Connect to RFD40")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    
                    // Error State Actions (retry + reset)
                    if rfidService.connectionState == .error {
                        VStack(spacing: 12) {
                            Button {
                                rfidService.connectToReader()
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Retry Connection")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            
                            Button {
                                rfidService.disconnect()
                            } label: {
                                HStack {
                                    Image(systemName: "xmark.circle")
                                    Text("Reset Connection")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.2))
                                .foregroundColor(.red)
                                .cornerRadius(10)
                            }
                            
                            // Power cycle help
                            VStack(alignment: .leading, spacing: 8) {
                                Text("If connection keeps failing:")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("1. Hold power button until RFD40 turns off")
                                    Text("2. Wait 5 seconds")
                                    Text("3. Power back on")
                                    Text("4. Tap 'Retry Connection'")
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    
                    // Disconnect Button (show when ready)
                    if rfidService.connectionState == .ready {
                        Button {
                            rfidService.disconnect()
                        } label: {
                            HStack {
                                Image(systemName: "xmark.circle")
                                Text("Disconnect")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.2))
                            .foregroundColor(.red)
                            .cornerRadius(10)
                        }
                    }
                    
                    // MARK: - Session Controls (only show when ready)
                    if rfidService.connectionState == .ready {
                        VStack(spacing: 16) {
                            // Session Type Picker
                            if rfidService.currentSession == nil {
                                Picker("Session Type", selection: $selectedSessionType) {
                                    Text("Input").tag(ScanSession.SessionType.input)
                                    Text("Output").tag(ScanSession.SessionType.output)
                                    Text("Inventory").tag(ScanSession.SessionType.inventory)
                                }
                                .pickerStyle(.segmented)
                            }
                            
                            // Start/Stop Session Button
                            Button {
                                if rfidService.currentSession != nil {
                                    Task {
                                        await rfidService.stopSession()
                                    }
                                } else {
                                    Task {
                                        await rfidService.startSession(
                                            type: selectedSessionType,
                                            locationId: selectedLocationId
                                        )
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: rfidService.currentSession != nil ? "stop.circle.fill" : "play.circle.fill")
                                    Text(rfidService.currentSession != nil ? "Stop Session" : "Start Session")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(rfidService.currentSession != nil ? Color.red : Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .disabled(rfidService.currentSession == nil && (selectedLocationId == nil || selectedLocationId?.isEmpty == true))
                            
                            if rfidService.currentSession == nil && (selectedLocationId == nil || selectedLocationId?.isEmpty == true) {
                                Text("Select a location to start a session.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // MARK: - Session Stats (show when active)
                    if let session = rfidService.currentSession {
                        VStack(alignment: .leading, spacing: 12) {
                            let locName = locationService.getLocation(id: session.locationId ?? "")?.displayName
                            Text(locName != nil ? "Active Session • \(locName!)" : "Active Session")
                                .font(.headline)
                            
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Session Type")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(session.sessionType.rawValue.capitalized)
                                        .font(.subheadline)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing) {
                                    Text("Tags Read")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(rfidService.totalTagsRead)")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            if let lastTag = rfidService.lastTagRead {
                                Divider()
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Last Tag Read")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text(lastTag.rfidTag)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.primary)
                                    
                                    HStack {
                                        Text("RSSI:")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("\(lastTag.rssi) dBm")
                                            .font(.caption2)
                                            .foregroundColor(signalColor(rssi: lastTag.rssi))
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(uiColor: .systemGray6))
                        .cornerRadius(12)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("RFID Scanner")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            // Refresh locations automatically when network comes back
            .onChange(of: networkMonitor.isConnected) { isOnline in
                if isOnline {
                    Task { await locationService.refresh() }
                }
            }
        }
    }
    
    // MARK: - Helper Properties
    
    private var statusColor: Color {
        switch rfidService.connectionState {
        case .ready:
            return .green
        case .connecting, .discovering, .validating:
            return .yellow
        case .disconnected:
            return .gray
        case .error:
            return .red
        }
    }
    
    private var batteryIcon: String {
        switch rfidService.batteryLevel {
        case 75...100:
            return "battery.100"
        case 50..<75:
            return "battery.75"
        case 25..<50:
            return "battery.50"
        case 10..<25:
            return "battery.25"
        default:
            return "battery.0"
        }
    }
    
    private var batteryColor: Color {
        rfidService.batteryLevel < 20 ? .red : .primary
    }
    
    private func signalColor(rssi: Int) -> Color {
        switch rssi {
        case -50...0:
            return .green
        case -70..<(-50):
            return .orange
        default:
            return .red
        }
    }
    
    private var syncColor: Color {
        if queueService.lastFlushFailed > 0 {
            return .red
        } else if queueService.lastFlushSucceeded > 0 {
            return .green
        } else {
            return .secondary
        }
    }
    
    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}

// MARK: - Settings View (Placeholder)

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var prefs = AppPreferences.shared
    @State private var rssiChoices: [Int] = [-70, -60, -55, -50, -45, -40]
    
    var body: some View {
        NavigationStack {
            List {
                Section("Scanning") {
                    Toggle("Trigger-driven scanning", isOn: $prefs.triggerScanning)
                    Toggle("Unique per session", isOn: $prefs.uniquePerSession)
                    Picker("Minimum RSSI", selection: Binding(
                        get: { prefs.minAcceptedRSSI ?? Int.min },
                        set: { value in
                            prefs.minAcceptedRSSI = (value == Int.min) ? nil : value
                        }
                    )) {
                        Text("Off").tag(Int.min)
                        ForEach(rssiChoices, id: \.self) { val in
                            Text("\(val) dBm").tag(val)
                        }
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("App Version")
                        Spacer()
                        Text(AppConfig.appVersion)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .environmentObject(RFIDService.shared)
}
