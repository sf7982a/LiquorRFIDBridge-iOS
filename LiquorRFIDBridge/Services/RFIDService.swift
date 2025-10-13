//
//  RFIDService.swift
//  LiquorRFIDBridge
//

import Foundation
import Combine
import ZebraRfidSdkFramework

class RFIDService: NSObject, ObservableObject {
    
    @Published var isConnected: Bool = false
    @Published var isScanning: Bool = false
    @Published var batteryLevel: Int = 100
    @Published var lastTagRead: RFIDTag?
    @Published var totalTagsRead: Int = 0
    @Published var currentSession: ScanSession?
    @Published var errorMessage: String?
    
    private var apiInstance: srfidISdkApi?
    private var connectedReaderID: Int32 = -1
    private var recentTags: [String: Date] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    private var supabaseService: SupabaseService
    private var queueService: QueueService
    private var networkMonitor: NetworkMonitor
    
    static let shared = RFIDService()
    
    private override init() {
        self.supabaseService = SupabaseService.shared
        self.queueService = QueueService(networkMonitor: NetworkMonitor())
        self.networkMonitor = NetworkMonitor()
        super.init()
        setupSDK()
    }
    
    private func setupSDK() {
        apiInstance = srfidSdkFactory.createRfidSdkApiInstance()
        apiInstance?.srfidSetDelegate(self)
        apiInstance?.srfidSetOperationalMode(Int32(SRFID_OPMODE_MFI))
        
        let eventMask = Int32(SRFID_EVENT_READER_APPEARANCE |
                             SRFID_EVENT_READER_DISAPPEARANCE |
                             SRFID_EVENT_SESSION_ESTABLISHMENT |
                             SRFID_EVENT_SESSION_TERMINATION |
                             SRFID_EVENT_MASK_READ |
                             SRFID_EVENT_MASK_STATUS |
                             SRFID_EVENT_MASK_BATTERY |
                             SRFID_EVENT_MASK_TRIGGER)
        
        apiInstance?.srfidSubsribe(forEvents: eventMask)
        apiInstance?.srfidEnableAvailableReadersDetection(true)
        apiInstance?.srfidEnableAutomaticSessionReestablishment(true)
        
        print("✅ Zebra SDK initialized")
    }
    
    func configure(supabase: SupabaseService, queue: QueueService, network: NetworkMonitor) {
        self.supabaseService = supabase
        self.queueService = queue
        self.networkMonitor = network
    }
    
    func connectToReader() {
        guard let api = apiInstance else {
            print("❌ SDK not initialized")
            return
        }
        
        var availableReaders: NSMutableArray?
        api.srfidGetAvailableReadersList(&availableReaders)
        
        guard let readers = availableReaders, readers.count > 0,
              let reader = readers[0] as? srfidReaderInfo else {
            print("⚠️ No readers found")
            DispatchQueue.main.async {
                self.errorMessage = "No RFID reader found. Make sure RFD40 is paired via Bluetooth."
            }
            return
        }
        
        let readerID = reader.getReaderID()
        let result = api.srfidEstablishCommunicationSession(readerID)
        
        if result == SRFID_RESULT_SUCCESS {
            print("✅ Connecting to reader: \(reader.getReaderName() ?? "Unknown")")
        } else {
            print("❌ Failed to connect: \(result)")
            DispatchQueue.main.async {
                self.errorMessage = "Failed to connect to reader"
            }
        }
    }
    
    func disconnect() {
        guard connectedReaderID != -1 else { return }
        apiInstance?.srfidTerminateCommunicationSession(connectedReaderID)
        print("🔌 Disconnected from reader")
    }
    
    func startSession(type: ScanSession.SessionType, locationId: String?) async {
        guard isConnected else {
            print("❌ Reader not connected")
            return
        }
        
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
            }
            
            startRapidRead()
            print("✅ Session started: \(session.id)")
        } catch {
            print("❌ Failed to create session: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.errorMessage = "Failed to start session: \(error.localizedDescription)"
            }
        }
    }
    
    func stopSession() async {
        guard let session = currentSession else { return }
        
        stopRapidRead()
        
        do {
            try await supabaseService.updateSession(
                id: session.id,
                status: .stopped,
                bottleCount: totalTagsRead
            )
            
            DispatchQueue.main.async {
                self.currentSession = nil
            }
            
            print("✅ Session stopped: \(session.id)")
        } catch {
            print("❌ Failed to stop session: \(error)")
        }
    }
    
    private func startRapidRead() {
        guard let api = apiInstance, connectedReaderID != -1 else { return }
        
        let reportConfig = srfidReportConfig()
        reportConfig.setIncRSSI(true)
        reportConfig.setIncPC(true)
        reportConfig.setIncFirstSeenTime(true)
        
        let accessConfig = srfidAccessConfig()
        accessConfig.setPower(270)
        accessConfig.setDoSelect(false)
        
        var statusMsg: NSString?
        
        print("🔧 Starting inventory (EPC memory bank)")
        
        let result = api.srfidStartInventory(
            connectedReaderID,
            aMemoryBank: SRFID_MEMORYBANK_EPC,
            aReportConfig: reportConfig,
            aAccessConfig: accessConfig,
            aStatusMessage: &statusMsg
        )
        
        if result == SRFID_RESULT_SUCCESS {
            DispatchQueue.main.async {
                self.isScanning = true
            }
            print("🔍 Scanning started with EPC memory bank")
        } else {
            let errorMsg = statusMsg as String? ?? "Unknown"
            print("❌ Scan failed - Result: \(result)")
            print("❌ Status: \(errorMsg)")
            
            DispatchQueue.main.async {
                self.errorMessage = "Scanning failed: \(errorMsg)"
            }
        }
    }
    
    private func stopRapidRead() {
        guard let api = apiInstance, connectedReaderID != -1 else { return }
        
        var statusMsg: NSString?
        api.srfidStopInventory(connectedReaderID, aStatusMessage: &statusMsg)
        
        DispatchQueue.main.async {
            self.isScanning = false
        }
        
        print("⏸️ Scanning stopped")
    }
    
    private func handleTagRead(rfidTag: String, rssi: Int) {
        if let lastSeen = recentTags[rfidTag] {
            let timeSinceLastSeen = Date().timeIntervalSince(lastSeen)
            if timeSinceLastSeen < AppConfig.duplicateFilterWindow {
                return
            }
        }
        
        recentTags[rfidTag] = Date()
        
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
        }
        
        Task {
            if networkMonitor.isConnected {
                do {
                    try await supabaseService.insertTag(tag)
                } catch {
                    print("❌ Failed to insert tag, queueing: \(error)")
                    queueService.enqueue(tag: tag)
                }
            } else {
                queueService.enqueue(tag: tag)
            }
        }
        
        print("📡 Tag read: \(rfidTag) RSSI: \(rssi) dBm")
    }
    
    func getReaderInfo() async -> String? {
        guard let api = apiInstance, connectedReaderID != -1 else { return nil }
        
        var versionInfo: srfidReaderVersionInfo?
        var statusMsg: NSString?
        
        let result = api.srfidGetReaderVersionInfo(
            connectedReaderID,
            aReaderVersionInfo: &versionInfo,
            aStatusMessage: &statusMsg
        )
        
        if result == SRFID_RESULT_SUCCESS, let info = versionInfo {
            let fw = info.getDeviceVersion() ?? "Unknown"
            let bt = info.getBluetoothVersion() ?? "Unknown"
            return "FW: \(fw), BT: \(bt)"
        }
        
        return nil
    }
    
    func clearDuplicateFilter() {
        recentTags.removeAll()
        print("🗑️ Duplicate filter cleared")
    }
    
    private func configureTriggers() {
        guard let api = apiInstance, connectedReaderID != -1 else { return }
        
        let startTrigger = srfidStartTriggerConfig()
        startTrigger.setStartOnHandheldTrigger(false)
        startTrigger.setStartDelay(0)
        startTrigger.setRepeatMonitoring(false)
        
        var statusMsg: NSString?
        var result = api.srfidSetStartTriggerConfiguration(
            connectedReaderID,
            aStartTriggeConfig: startTrigger,
            aStatusMessage: &statusMsg
        )
        
        if result == SRFID_RESULT_SUCCESS {
            print("✅ Start trigger configured")
        } else {
            print("⚠️ Start trigger failed: \(statusMsg ?? "Unknown")")
        }
        
        let stopTrigger = srfidStopTriggerConfig()
        stopTrigger.setStopOnHandheldTrigger(false)
        stopTrigger.setStopOnTimeout(false)
        stopTrigger.setStopOnTagCount(false)
        stopTrigger.setStopOnInventoryCount(false)
        stopTrigger.setStopOnAccessCount(false)
        
        result = api.srfidSetStopTriggerConfiguration(
            connectedReaderID,
            aStopTriggeConfig: stopTrigger,
            aStatusMessage: &statusMsg
        )
        
        if result == SRFID_RESULT_SUCCESS {
            print("✅ Stop trigger configured")
        } else {
            print("⚠️ Stop trigger failed: \(statusMsg ?? "Unknown")")
        }
    }
    private func configureAntenna() {
        guard let api = apiInstance, connectedReaderID != -1 else { return }
        
        // Get current config first
        var currentConfig: srfidAntennaConfiguration?
        var statusMsg: NSString?
        
        var result = api.srfidGetAntennaConfiguration(
            connectedReaderID,
            aAntennaConfiguration: &currentConfig,
            aStatusMessage: &statusMsg
        )
        
        if result == SRFID_RESULT_SUCCESS, let config = currentConfig {
            // Modify existing config
            config.setPower(270)
            config.setDoSelect(false)
            
            // Set it back
            result = api.srfidSetAntennaConfiguration(
                connectedReaderID,
                aAntennaConfiguration: config,
                aStatusMessage: &statusMsg
            )
            
            if result == SRFID_RESULT_SUCCESS {
                print("✅ Antenna configured: 27.0 dBm")
            } else {
                print("⚠️ Antenna set failed: \(statusMsg ?? "Unknown")")
            }
        } else {
            print("⚠️ Antenna get failed: \(statusMsg ?? "Unknown")")
        }
    }

    private func configureSingulation() {
        guard let api = apiInstance, connectedReaderID != -1 else { return }
        
        // Get current config first
        var currentConfig: srfidSingulationConfig?
        var statusMsg: NSString?
        
        var result = api.srfidGetSingulationConfiguration(
            connectedReaderID,
            aSingulationConfig: &currentConfig,
            aStatusMessage: &statusMsg
        )
        
        if result == SRFID_RESULT_SUCCESS, let config = currentConfig {
            // Modify existing config
            config.setSession(SRFID_SESSION_S1)
            config.setTagPopulation(30)
            
            // Set it back
            result = api.srfidSetSingulationConfiguration(
                connectedReaderID,
                aSingulationConfig: config,
                aStatusMessage: &statusMsg
            )
            
            if result == SRFID_RESULT_SUCCESS {
                print("✅ Singulation configured")
            } else {
                print("⚠️ Singulation set failed: \(statusMsg ?? "Unknown")")
            }
        } else {
            print("⚠️ Singulation get failed: \(statusMsg ?? "Unknown")")
        }
    }
}

// MARK: - Zebra SDK Delegate

extension RFIDService: srfidISdkApiDelegate {
    
    func srfidEventWifiScan(_ readerID: Int32, wlanSCanObject wlanScanObject: srfidWlanScanList!) {
        print("📶 WiFi scan event: \(readerID)")
    }
    
    func srfidEventIOTSatusNotity(_ readerID: Int32, aIOTStatusEvent iotStatusEvent: srfidIOTStatusEvent!) {
        print("🌐 IOT status event: \(readerID)")
    }
    
    func srfidEventConnectedInterfaceNotity(_ readerID: Int32, aConnectedInterfaceEvent connectedInterfaceEvent: sfidConnectedInterfaceEvent!) {
        print("🔌 Interface event: \(readerID)")
    }
    
    func srfidEventReaderAppeared(_ availableReader: srfidReaderInfo!) {
        print("📱 Reader appeared: \(availableReader.getReaderName() ?? "Unknown")")
        
        guard let api = apiInstance else { return }
        
        let readerID = availableReader.getReaderID()
        let result = api.srfidEstablishCommunicationSession(readerID)
        
        if result == SRFID_RESULT_SUCCESS {
            print("✅ Connecting to: \(availableReader.getReaderName() ?? "Unknown")")
        } else {
            print("❌ Failed to connect: \(result)")
            DispatchQueue.main.async {
                self.errorMessage = "Failed to connect to reader"
            }
        }
    }
    
    func srfidEventReaderDisappeared(_ readerID: Int32) {
        print("📱 Reader disappeared: \(readerID)")
        DispatchQueue.main.async {
            self.isConnected = false
            self.isScanning = false
        }
    }
    
    func srfidEventCommunicationSessionEstablished(_ activeReader: srfidReaderInfo!) {
        connectedReaderID = activeReader.getReaderID()
        
        DispatchQueue.main.async {
            self.isConnected = true
            self.errorMessage = nil
        }
        
        print("✅ Reader connected: \(activeReader.getReaderName() ?? "Unknown")")
        apiInstance?.srfidRequestBatteryStatus(connectedReaderID)
        
        // Use existing config from Zebra 123RFID app - don't try to change anything
        print("📋 Using saved reader configuration")
    }
    
    func srfidEventCommunicationSessionTerminated(_ readerID: Int32) {
        connectedReaderID = -1
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.isScanning = false
        }
        
        print("🔌 Reader disconnected")
    }
    
    func srfidEventReadNotify(_ readerID: Int32, aTagData tagData: srfidTagData!) {
        guard let tagId = tagData.getTagId() else { return }
        let rssi = Int(tagData.getPeakRSSI())
        handleTagRead(rfidTag: tagId, rssi: rssi)
    }
    
    func srfidEventBatteryNotity(_ readerID: Int32, aBatteryEvent batteryEvent: srfidBatteryEvent!) {
        let level = Int(batteryEvent.getPowerLevel())
        DispatchQueue.main.async {
            self.batteryLevel = level
        }
        print("🔋 Battery: \(level)%")
    }
    
    func srfidEventStatusNotify(_ readerID: Int32, aEvent event: SRFID_EVENT_STATUS, aNotification notificationData: Any!) {
        switch event {
        case SRFID_EVENT_STATUS_OPERATION_START:
            print("▶️ Operation started")
        case SRFID_EVENT_STATUS_OPERATION_STOP:
            print("⏹️ Operation stopped")
        default:
            break
        }
    }
    
    func srfidEventTriggerNotify(_ readerID: Int32, aTriggerEvent triggerEvent: SRFID_TRIGGEREVENT) {
        switch triggerEvent {
        case SRFID_TRIGGEREVENT_PRESSED:
            print("🔘 Trigger pressed")
        case SRFID_TRIGGEREVENT_RELEASED:
            print("🔘 Trigger released")
        default:
            break
        }
    }
    
    func srfidEventProximityNotify(_ readerID: Int32, aProximityPercent proximityPercent: Int32) {
        // Future: tag locationing
    }
    
    func srfidEventMultiProximityNotify(_ readerID: Int32, aTagData tagData: srfidTagData!) {
        // Future: multi-tag locationing
    }
}
