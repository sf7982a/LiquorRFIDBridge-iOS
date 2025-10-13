//
//  HomeView.swift
//  LiquorRFIDBridge
//
//  Main dashboard for RFID scanning operations
//

import SwiftUI

struct HomeView: View {
    
    @StateObject private var rfidService = RFIDService.shared
    @State private var selectedSessionType: ScanSession.SessionType = .input
    @State private var selectedLocation: String?
    @State private var isStartingSession = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // MARK: - Reader Status Card
                    StatusCard(
                        isConnected: rfidService.isConnected,
                        batteryLevel: rfidService.batteryLevel,
                        errorMessage: rfidService.errorMessage
                    )
                    
                    // MARK: - Session Controls
                    if rfidService.isConnected {
                        if rfidService.currentSession == nil {
                            // Start Session UI
                            VStack(spacing: 16) {
                                sessionTypePicker
                                
                                Button(action: startSession) {
                                    HStack {
                                        if isStartingSession {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        } else {
                                            Image(systemName: "play.circle.fill")
                                        }
                                        Text(isStartingSession ? "Starting..." : "Start Session")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                                .disabled(isStartingSession)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(16)
                        } else {
                            // Active Session UI
                            ActiveSessionCard(
                                sessionType: rfidService.currentSession?.sessionType ?? .input,
                                tagsRead: rfidService.totalTagsRead,
                                isScanning: rfidService.isScanning,
                                onStop: stopSession
                            )
                        }
                    } else {
                        // Connect Reader UI
                        ConnectReaderCard(onConnect: connectReader)
                    }
                    
                    // MARK: - Last Tag Read
                    if let lastTag = rfidService.lastTagRead {
                        LastTagCard(tag: lastTag)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("RFID Bridge")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
    }
    
    // MARK: - Session Type Picker
    
    private var sessionTypePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session Type")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Picker("Session Type", selection: $selectedSessionType) {
                Text("📥 Input").tag(ScanSession.SessionType.input)
                Text("📤 Output").tag(ScanSession.SessionType.output)
                Text("📊 Inventory").tag(ScanSession.SessionType.inventory)
            }
            .pickerStyle(SegmentedPickerStyle())
        }
    }
    
    // MARK: - Actions
    
    private func connectReader() {
        rfidService.connectToReader()
    }
    
    private func startSession() {
        isStartingSession = true
        
        Task {
            await rfidService.startSession(
                type: selectedSessionType,
                locationId: selectedLocation
            )
            
            await MainActor.run {
                isStartingSession = false
            }
        }
    }
    
    private func stopSession() {
        Task {
            await rfidService.stopSession()
        }
    }
}

// MARK: - Status Card

struct StatusCard: View {
    let isConnected: Bool
    let batteryLevel: Int
    let errorMessage: String?
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isConnected ? .green : .red)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(isConnected ? "Reader Connected" : "No Reader")
                        .font(.headline)
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    } else if isConnected {
                        HStack(spacing: 4) {
                            Image(systemName: "battery.100")
                                .foregroundColor(batteryColor)
                            Text("\(batteryLevel)%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        }
    }
    
    private var batteryColor: Color {
        switch batteryLevel {
        case 0..<20: return .red
        case 20..<50: return .orange
        default: return .green
        }
    }
}

// MARK: - Connect Reader Card

struct ConnectReaderCard: View {
    let onConnect: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("No RFID Reader Connected")
                .font(.headline)
            
            Text("Make sure your RFD40 is paired via Bluetooth")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: onConnect) {
                HStack {
                    Image(systemName: "link")
                    Text("Connect Reader")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

// MARK: - Active Session Card

struct ActiveSessionCard: View {
    let sessionType: ScanSession.SessionType
    let tagsRead: Int
    let isScanning: Bool
    let onStop: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Session Info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sessionTypeText)
                        .font(.headline)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isScanning ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(isScanning ? "Scanning..." : "Ready")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(tagsRead)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.blue)
                    Text("Tags Read")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Stop Button
            Button(action: onStop) {
                HStack {
                    Image(systemName: "stop.circle.fill")
                    Text("Stop Session")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    private var sessionTypeText: String {
        switch sessionType {
        case .input: return "📥 Input Session"
        case .output: return "📤 Output Session"
        case .inventory: return "📊 Inventory Session"
        }
    }
}

// MARK: - Last Tag Card

struct LastTagCard: View {
    let tag: RFIDTag
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Latest Tag")
                    .font(.headline)
                Spacer()
                Text(tag.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("EPC:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(tag.rfidTag)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                }
                
                HStack {
                    Text("Signal:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(tag.rssi) dBm")
                        .font(.caption)
                        .foregroundColor(signalColor(rssi: tag.rssi))
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    private func signalColor(rssi: Int) -> Color {
        switch rssi {
        case -50...0: return .green
        case -70..<(-50): return .orange
        default: return .red
        }
    }
}
    
    // MARK: - Settings View Placeholder

    struct SettingsView: View {
        var body: some View {
            List {
                Section("App Info") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(AppConfig.appVersion)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Device")
                        Spacer()
                        Text(AppConfig.deviceName)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Database") {
                    HStack {
                        Text("Organization ID")
                        Spacer()
                        Text(AppConfig.organizationId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Preview

    #Preview {
        HomeView()
    }
    // MARK: - Preview
    
    #Preview {
        HomeView()
    }

