//
//  SupabaseService.swift
//  LiquorRFIDBridge
//

import Foundation

class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    
    @Published var isUploading: Bool = false
    @Published var lastError: String?
    
    private let session = URLSession.shared
    private var networkMonitor: NetworkMonitor?
    
    private init() {}
    
    // MARK: - Dependency Injection
    func configure(networkMonitor: NetworkMonitor) {
        self.networkMonitor = networkMonitor
    }
    
    // MARK: - Create Session
    func createSession(_ sessionData: ScanSession) async throws -> String {
        guard networkMonitor?.isConnected ?? false else { throw SupabaseError.offline }
        let url = URL(string: AppConfig.fnCreateSession)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (key, value) in AppConfig.supabaseHeaders { request.setValue(value, forHTTPHeaderField: key) }
        // Function expects snake_case keys
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(sessionData)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let s = String(data: data, encoding: .utf8) { print("Session creation error: \(s)") }
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
        print("Session created: \(sessionData.id)")
        return sessionData.id.uuidString
    }
    
    // MARK: - Insert Tag
    func insertTag(_ tag: RFIDTag) async throws {
        guard networkMonitor?.isConnected ?? false else { throw SupabaseError.offline }
        await MainActor.run { self.isUploading = true }
        defer { Task { @MainActor in self.isUploading = false } }
        // Use batch function with a single item
        let url = URL(string: AppConfig.fnBatchInsertScans)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (key, value) in AppConfig.supabaseHeaders { request.setValue(value, forHTTPHeaderField: key) }
        // Build batch body
        let body: [String: Any?] = [
            "organization_id": tag.organizationId,
            "session_id": tag.sessionId?.uuidString,
            "scans": [
                tag.toDictionary()
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body.compactMapValues { $0 }, options: [])
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let s = String(data: data, encoding: .utf8) { print("Tag insert error: \(s)") }
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
        print("Tag inserted (via batch): \(tag.rfidTag)")
    }
    
    // MARK: - Update Session
    func updateSession(id: UUID, status: ScanSession.SessionStatus, bottleCount: Int? = nil) async throws {
        guard networkMonitor?.isConnected ?? false else { throw SupabaseError.offline }
        let url = URL(string: AppConfig.fnCompleteSession)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (key, value) in AppConfig.supabaseHeaders { request.setValue(value, forHTTPHeaderField: key) }
        var payload: [String: Any] = [
            "id": id.uuidString,
            "status": status.rawValue
        ]
        if status == .stopped || status == .completed {
            payload["ended_at"] = ISO8601DateFormatter().string(from: Date())
        }
        if let count = bottleCount { payload["bottle_count"] = count }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let s = String(data: data, encoding: .utf8) { print("Session update error: \(s)") }
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
        print("Session updated (function): \(id)")
    }
    
    // MARK: - Batch Insert
    func batchInsertTags(_ tags: [RFIDTag]) async throws {
        guard !tags.isEmpty else { return }
        
        let batchSize = 50
        var successCount = 0
        
        for batchStart in stride(from: 0, to: tags.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, tags.count)
            let batch = Array(tags[batchStart..<batchEnd])
            try await batchInsertViaFunction(batch)
            successCount += batch.count
        }
        
        print("Batch inserted \(successCount)/\(tags.count) tags")
    }

    // MARK: - Helpers
    private func batchInsertViaFunction(_ tags: [RFIDTag]) async throws {
        guard networkMonitor?.isConnected ?? false else { throw SupabaseError.offline }
        guard let anyTag = tags.first else { return }
        // 1) Always write raw scans for audit
        do {
            let url = URL(string: AppConfig.fnBatchInsertScans)!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            for (key, value) in AppConfig.supabaseHeaders { request.setValue(value, forHTTPHeaderField: key) }
            let scans = tags.map { $0.toDictionary() }
            let body: [String: Any] = [
                "organization_id": anyTag.organizationId,
                "session_id": anyTag.sessionId?.uuidString as Any,
                "scans": scans
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
            guard (200...299).contains(httpResponse.statusCode) else {
                if let s = String(data: data, encoding: .utf8) { print("Batch insert error: \(s)") }
                throw SupabaseError.httpError(httpResponse.statusCode)
            }
        } catch {
            // Surface the raw scans failure
            throw error
        }
        
        // 2) Upsert bottles and (when inventory) write daily counts
        // Require a location_id to be present (inventory sessions enforce this)
        if let loc = anyTag.locationId {
            var req = URLRequest(url: URL(string: AppConfig.fnScanUpsert)!)
            req.httpMethod = "POST"
            for (key, value) in AppConfig.supabaseHeaders { req.setValue(value, forHTTPHeaderField: key) }
            let tagsSlim = tags.map { ["rfid_tag": $0.rfidTag, "rssi": $0.rssi, "timestamp": ISO8601DateFormatter().string(from: $0.timestamp)] }
            let body: [String: Any] = [
                "organization_id": anyTag.organizationId,
                "session_id": anyTag.sessionId?.uuidString as Any,
                "location_id": loc,
                // Optional: "session_type" can be omitted; RPC resolves from session_id
                "tags": tagsSlim
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            // Await RPC; if it fails we still preserve raw scans already written
            _ = try? await self.session.data(for: req)
        }
    }
    
    // MARK: - Errors
    enum SupabaseError: Error, LocalizedError {
        case offline
        case invalidResponse
        case httpError(Int)
        case encodingError
        case decodingError
        
        var errorDescription: String? {
            switch self {
            case .offline:
                return "No internet connection"
            case .invalidResponse:
                return "Invalid server response"
            case .httpError(let code):
                return "Server error: \(code)"
            case .encodingError:
                return "Failed to encode data"
            case .decodingError:
                return "Failed to decode response"
            }
        }
    }
}
