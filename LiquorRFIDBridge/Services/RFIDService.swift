//
//  RFIDService.swift
//  LiquorRFIDBridge
//
//  FINAL VERSION: Lightning + RFD40 Premium Plus
//  - NO CONFIG: Factory defaults = TAGS SCAN
//  - Start inventory immediately
//  - Auto-retry on failure
//  - All @Published on main thread
//

import Foundation
import Combine
import ZebraRfidSdkFramework
import CoreBluetooth
import os.log

class RFIDService: NSObject, ObservableObject {
    
    @Published var isConnected: Bool = false
    @Published var isScanning: Bool = false
    @Published var batteryLevel: Int = 100
    @Published var lastTagRead: RFIDTag?
    @Published var totalTagsRead: Int = 0
    @Published var currentSession: ScanSession?
    @Published var errorMessage: String?
    @Published var connectionState: ConnectionState = .disconnected
    
    enum ConnectionState: String {
        case disconnected = "Disconnected"
        case discovering = "Searching..."
        case connecting = "Connecting..."
        case validating = "Validating..."
        case ready = "Ready"
        case error = "Error"
    }
    
    private var apiInstance: srfidISdkApi?
    private var connectedReaderID: Int32 = -1
    private var recentTags: [String: Date] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var supabaseService: SupabaseService
    private var queueService: QueueService
    private var networkMonitor: NetworkMonitor
    private var bluetoothManager: CBCentralManager?
    private var isBluetoothReady = false
    private var asciiConnectAttempts = 0
    private let maxAsciiConnectAttempts = 3
    private var inventoryStartAttempts = 0
    private let maxInventoryStartAttempts = 10
    private var isStartingSessionOp = false
    private var isStoppingSessionOp = false
    private var inventoryReportConfig: srfidReportConfig?
    private var sessionSeenTags = Set<String>()
    private let logger = OSLog(subsystem: "com.liquorrfid.bridge", category: "rfid")
    @Published var interfaceDescription: String = "Unknown"
    
    static let shared = RFIDService()
    
    private override init() {
        self.supabaseService = SupabaseService.shared
        self.queueService = QueueService(networkMonitor: NetworkMonitor())
        self.networkMonitor = NetworkMonitor()
        super.init()
        
        print("Waiting for iOS Bluetooth to power on...")
        os_log("Waiting for iOS Bluetooth to power on...", log: logger, type: .info)
        bluetoothManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - SDK Setup
    private func setupSDK() {
        print("=== INITIALIZING ZEBRA RFID SDK ===")
        os_log("=== INITIALIZING ZEBRA RFID SDK ===", log: logger, type: .info)
        
        apiInstance = srfidSdkFactory.createRfidSdkApiInstance()
        guard let api = apiInstance else {
            print("Failed to create SDK instance!")
            updateConnectionState(.error, message: "SDK failed")
            return
        }
        
        let version = api.srfidGetSdkVersion() ?? "unknown"
        print("SDK Version: \(version)")
        
        api.srfidSetDelegate(self)
        print("Delegate set")

        // Prefer MFi/iAP2 for RFD40 Premium Plus when using Lightning
        _ = api.srfidSetOperationalMode(Int32(Int(SRFID_OPMODE_MFI)))

        let eventMask = Int32(SRFID_EVENT_READER_APPEARANCE |
                            SRFID_EVENT_READER_DISAPPEARANCE |
                            SRFID_EVENT_SESSION_ESTABLISHMENT |
                            SRFID_EVENT_SESSION_TERMINATION |
                            SRFID_EVENT_MASK_READ |
                            SRFID_EVENT_MASK_STATUS |
                            SRFID_EVENT_MASK_BATTERY |
                            SRFID_EVENT_MASK_CONNECTED_INTERFACE)
        
        if api.srfidSubsribe(forEvents: eventMask) == SRFID_RESULT_SUCCESS {
            print("Subscribed to events")
        }
        
        if api.srfidEnableAvailableReadersDetection(true) == SRFID_RESULT_SUCCESS {
            print("Reader detection enabled")
        }
        
        if api.srfidEnableAutomaticSessionReestablishment(true) == SRFID_RESULT_SUCCESS {
            print("Auto-reconnect enabled")
        }
        
        print("=== SDK READY ===")
        print("   Connect RFD40 via MFi (Bluetooth or Lightning) now...")
    }
    
    func connectToReader() {
        guard apiInstance != nil else {
            print("SDK not ready")
            return
        }
        updateConnectionState(.discovering)
        print("Waiting for RFD40 via Lightning...")
    }
    
    func disconnect() {
        guard connectedReaderID != -1, let api = apiInstance else { return }
        stopRapidRead()
        api.srfidTerminateCommunicationSession(connectedReaderID)
        connectedReaderID = -1
        updateConnectionState(.disconnected)
    }
    
    private func updateConnectionState(_ state: ConnectionState, message: String? = nil) {
        DispatchQueue.main.async {
            self.connectionState = state
            self.isConnected = (state == .ready)
            self.errorMessage = message
        }
    }
    
    // MARK: - SKIP CONFIG — USE FACTORY DEFAULTS
    private func configureAfterSession() {
        print("\nSKIPPING CONFIG — USING FACTORY DEFAULTS")
        DispatchQueue.main.async {
            self.updateConnectionState(.ready)
        }
        print("READER READY — START SCANNING!")
        if AppPreferences.shared.triggerScanning {
            self.establishAsciiConnectionAndStartDeferred()
        } else {
            self.establishAsciiConnectionAndStart()
        }
    }
    
    // MARK: - Scanning
    func startSession(type: ScanSession.SessionType, locationId: String?) async {
        guard connectionState == .ready else { return }
        if isStartingSessionOp || currentSession != nil { return }
        isStartingSessionOp = true
        defer { isStartingSessionOp = false }
        
        let session = ScanSession(
            organizationId: AppConfig.organizationId,
            locationId: locationId,
            userId: nil,
            sessionType: type,
            deviceName: AppConfig.deviceName,
            status: .active
        )
        
        do {
            _ = try await supabaseService.createSession(session)
            DispatchQueue.main.async {
                self.currentSession = session
                self.totalTagsRead = 0
                self.sessionSeenTags.removeAll()
            }
            
            print("Session created: \(session.id)")
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Session failed: \(error.localizedDescription)"
            }
        }
    }
    
    func stopSession() async {
        if isStoppingSessionOp { return }
        isStoppingSessionOp = true
        defer { isStoppingSessionOp = false }
        
        stopRapidRead()
        guard let session = currentSession else { return }
        try? await supabaseService.updateSession(id: session.id, status: .stopped, bottleCount: totalTagsRead)
        DispatchQueue.main.async {
            self.currentSession = nil
        }
        print("Session updated: \(session.id)")
    }
    
    private func startRapidRead() {
        guard let api = apiInstance, connectedReaderID != -1 else { return }
        
        print("STARTING INVENTORY WITH FACTORY SETTINGS...")
        
        let result = api.srfidStartInventory(
            connectedReaderID,
            aMemoryBank: SRFID_MEMORYBANK_EPC,
            aReportConfig: inventoryReportConfig,
            aAccessConfig: nil,
            aStatusMessage: nil
        )
        
        DispatchQueue.main.async {
            if result == SRFID_RESULT_SUCCESS {
                print("INVENTORY STARTED (NO CONFIG)")
                self.isScanning = true
                self.inventoryStartAttempts = 0
            } else {
                self.inventoryStartAttempts += 1
                if self.inventoryStartAttempts >= self.maxInventoryStartAttempts {
                    self.updateConnectionState(.error, message: "Inventory start failed repeatedly (\(result.rawValue))")
                    print("Start failed: \(result.rawValue) — giving up after \(self.inventoryStartAttempts) attempts")
                } else {
                    print("Start failed: \(result.rawValue) — retrying in 2s...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.startRapidRead()
                    }
                }
            }
        }
    }
    
    private func stopRapidRead() {
        guard let api = apiInstance, connectedReaderID != -1 else { return }
        api.srfidStopInventory(connectedReaderID, aStatusMessage: nil)
        DispatchQueue.main.async {
            self.isScanning = false
        }
    }
    
    private func handleTagRead(rfidTag: String, rssi: Int) {
        // Optional RSSI gate to ignore distant reads
        if let minRSSI = AppPreferences.shared.minAcceptedRSSI, rssi < minRSSI {
            return
        }
        
        // Prune stale entries to prevent unbounded growth
        let now = Date()
        recentTags = recentTags.filter { now.timeIntervalSince($0.value) <= AppConfig.duplicateFilterWindow }

        // Session-level de-duplication (count each EPC once per session)
        if AppPreferences.shared.uniquePerSession, currentSession != nil {
            if sessionSeenTags.contains(rfidTag) {
                return
            } else {
                sessionSeenTags.insert(rfidTag)
            }
        }
        
        // Time-window duplicate filtering (fallback / when no session)
        if let last = recentTags[rfidTag], now.timeIntervalSince(last) < AppConfig.duplicateFilterWindow {
            return
        }
        recentTags[rfidTag] = now
        
        let tag = RFIDTag(
            organizationId: AppConfig.organizationId,
            sessionId: currentSession?.id,
            locationId: currentSession?.locationId,
            rfidTag: rfidTag,
            rssi: rssi
        )
        
        DispatchQueue.main.async {
            self.lastTagRead = tag
            self.totalTagsRead += 1
            self.objectWillChange.send()
        }
        
        Task {
            if networkMonitor.isConnected {
                try? await supabaseService.insertTag(tag)
            } else {
                queueService.enqueue(tag: tag)
            }
        }
        
        print("Tag: \(rfidTag) | RSSI: \(rssi) dBm")
    }
    
    // MARK: - ASCII Connection
    private func establishAsciiConnectionAndStart() {
        guard let api = apiInstance, connectedReaderID != -1 else { return }
        
        let result = api.srfidEstablishAsciiConnection(connectedReaderID, aPassword: "")
        if result == SRFID_RESULT_SUCCESS {
            print("ASCII connection established")
            asciiConnectAttempts = 0
            configureReporting()
            startRapidRead()
            return
        }
        
        if result == SRFID_RESULT_WRONG_ASCII_PASSWORD {
            print("ASCII connection failed: wrong password")
            updateConnectionState(.error, message: "ASCII password required or incorrect")
            return
        }
        
        asciiConnectAttempts += 1
        if asciiConnectAttempts >= maxAsciiConnectAttempts {
            print("ASCII connection failed (\(result.rawValue)) — giving up after \(asciiConnectAttempts) attempts")
            updateConnectionState(.error, message: "ASCII connection failed (\(result.rawValue))")
            return
        }
        
        print("ASCII connection failed (\(result.rawValue)) — retrying in 2s...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.establishAsciiConnectionAndStart()
        }
    }

    // Establish ASCII connection but do not auto-start inventory (trigger-driven mode)
    private func establishAsciiConnectionAndStartDeferred() {
        guard let api = apiInstance, connectedReaderID != -1 else { return }
        let result = api.srfidEstablishAsciiConnection(connectedReaderID, aPassword: "")
        if result == SRFID_RESULT_SUCCESS {
            print("ASCII connection established (deferred start)")
            asciiConnectAttempts = 0
            configureReporting()
            return
        }
        if result == SRFID_RESULT_WRONG_ASCII_PASSWORD {
            print("ASCII connection failed: wrong password")
            updateConnectionState(.error, message: "ASCII password required or incorrect")
            return
        }
        asciiConnectAttempts += 1
        if asciiConnectAttempts >= maxAsciiConnectAttempts {
            print("ASCII connection failed (\(result.rawValue)) — giving up after \(asciiConnectAttempts) attempts")
            updateConnectionState(.error, message: "ASCII connection failed (\(result.rawValue))")
            return
        }
        print("ASCII connection failed (\(result.rawValue)) — retrying in 2s...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.establishAsciiConnectionAndStartDeferred()
        }
    }

    // MARK: - Reporting/De-dup Configuration
    private func configureReporting() {
        guard let api = apiInstance, connectedReaderID != -1 else { return }
        
        // Enable unique tag reporting to reduce duplicate EPC callbacks
        let unique = srfidUniqueTagsReport()
        unique.setUniqueTagsReportEnabled(true)
        _ = api.srfidSetUniqueTagReportConfiguration(connectedReaderID, aUtrConfiguration: unique, aStatusMessage: nil)
        
        // Configure tag report fields (include RSSI and TagSeenCount)
        let report = srfidReportConfig()
        report.setIncRSSI(true)
        report.setIncTagSeenCount(true)
        report.setIncFirstSeenTime(false)
        report.setIncLastSeenTime(false)
        report.setIncPC(false)
        report.setIncPhase(false)
        report.setIncChannelIndex(false)
        
        self.inventoryReportConfig = report
    }
    
    // MARK: - Dependency Injection
    func configure(supabase: SupabaseService, queue: QueueService, network: NetworkMonitor) {
        self.supabaseService = supabase
        self.queueService = queue
        self.networkMonitor = network
    }
}

// MARK: - Zebra SDK Delegate
extension RFIDService: srfidISdkApiDelegate {
    
    func srfidEventReaderAppeared(_ readerInfo: srfidReaderInfo?) {
        guard let info = readerInfo else { return }
        let id = info.getReaderID()
        let name = info.getReaderName() ?? "Unknown"
        
        print("\nREADER APPEARED: \(name) (ID: \(id))")
        
        if connectedReaderID == -1 {
            updateConnectionState(.connecting)
            apiInstance?.srfidEstablishCommunicationSession(id)
        }
    }
    
    func srfidEventReaderDisappeared(_ readerID: Int32) {
        print("Reader disappeared: \(readerID)")
        if readerID == connectedReaderID {
            connectedReaderID = -1
            updateConnectionState(.disconnected)
        }
    }
    
    func srfidEventCommunicationSessionEstablished(_ activeReader: srfidReaderInfo?) {
        guard let reader = activeReader else { return }
        connectedReaderID = reader.getReaderID()
        
        print("\nSESSION ESTABLISHED (ID: \(connectedReaderID))")
        print("   Protocol: MFi")
        
        // Request interface status so delegate logs whether it's Bluetooth or USB/Terminal
        apiInstance?.srfidRequestDeviceConnectionInterfaceStatus(connectedReaderID)
        
        // START IMMEDIATELY — NO CONFIG
        configureAfterSession()
    }
    
    func srfidEventCommunicationSessionTerminated(_ readerID: Int32) {
        if readerID == connectedReaderID {
            print("\nSESSION TERMINATED")
            connectedReaderID = -1
            updateConnectionState(.disconnected)
        }
    }
    
    func srfidEventReadNotify(_ readerID: Int32, aTagData tagData: srfidTagData?) {
        guard let tag = tagData, let epc = tag.getTagId() else { return }
        let rssi = Int(tag.getPeakRSSI())
        handleTagRead(rfidTag: epc, rssi: rssi)
    }
    
    func srfidEventBatteryNotity(_ readerID: Int32, aBatteryEvent batteryEvent: srfidBatteryEvent?) {
        guard let event = batteryEvent else { return }
        let level = Int(event.getPowerLevel())
        DispatchQueue.main.async {
            self.batteryLevel = level
        }
        print("Battery: \(level)%")
    }
    
    func srfidEventStatusNotify(_ readerID: Int32, aEvent event: SRFID_EVENT_STATUS, aNotification notificationData: Any?) {
        switch event {
        case SRFID_EVENT_STATUS_OPERATION_START:
            print("Inventory running")
        case SRFID_EVENT_STATUS_OPERATION_STOP:
            print("Inventory stopped")
        default:
            break
        }
    }
    
    // Trigger-driven scanning (optional)
    func srfidEventTriggerNotify(_ readerID: Int32, aTriggerEvent triggerEvent: SRFID_TRIGGEREVENT) {
        guard AppPreferences.shared.triggerScanning else { return }
        switch triggerEvent {
        case SRFID_TRIGGEREVENT_PRESSED:
            if !isScanning { startRapidRead() }
        case SRFID_TRIGGEREVENT_RELEASED:
            if isScanning { stopRapidRead() }
        default:
            break
        }
    }
    func srfidEventProximityNotify(_ readerID: Int32, aProximityPercent proximityPercent: Int32) {}
    func srfidEventMultiProximityNotify(_ readerID: Int32, aTagData tagData: srfidTagData?) {}
    func srfidEventWifiScan(_ readerID: Int32, wlanSCanObject wlanScanObject: srfidWlanScanList?) {}
    func srfidEventIOTSatusNotity(_ readerID: Int32, aIOTStatusEvent iotStatusEvent: srfidIOTStatusEvent?) {}
    func srfidEventConnectedInterfaceNotity(_ readerID: Int32, aConnectedInterfaceEvent connectedInterfaceEvent: sfidConnectedInterfaceEvent?) {
        guard let evt = connectedInterfaceEvent else { return }
        let type = evt.getConneted_Interface_Type()
        let desc: String
        switch type {
        case SRFID_CONNECTION_TYPE_BLUETOOTH:
            desc = "Bluetooth"
        case SRFID_CONNECTION_TYPE_USB:
            desc = "USB"
        case SRFID_CONNECTION_TYPE_TERMINAL:
            desc = "Terminal"
        case SRFID_CONNECTION_TYPE_ETHERNET:
            desc = "Ethernet"
        case SRFID_CONNECTION_TYPE_NO_INTERFACE:
            desc = "None"
        default:
            desc = "Unknown (\(type))"
        }
        print("Connected interface: \(desc)")
        DispatchQueue.main.async {
            self.interfaceDescription = desc
        }
    }
}

// MARK: - CoreBluetooth Delegate
extension RFIDService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn && !isBluetoothReady {
            isBluetoothReady = true
            setupSDK()
        } else if central.state != .poweredOn {
            updateConnectionState(.error, message: "Bluetooth off")
        }
    }
}
