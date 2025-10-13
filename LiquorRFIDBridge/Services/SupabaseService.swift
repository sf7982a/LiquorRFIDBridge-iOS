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
    
    func configure(networkMonitor: NetworkMonitor) {
        self.networkMonitor = networkMonitor
    }
    
    func createSession(_ sessionData: ScanSession) async throws -> String {
        guard networkMonitor?.isConnected ?? false else {
            throw SupabaseError.offline
        }
        
        let url = URL(string: AppConfig.scanSessionsEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        for (key, value) in AppConfig.supabaseHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(sessionData)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorString = String(data: data, encoding: .utf8) {
                print("❌ Session creation error: \(errorString)")
            }
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
        
        print("✅ Session created: \(sessionData.id)")
        return sessionData.id.uuidString
    }
    
    func insertTag(_ tag: RFIDTag) async throws {
        guard networkMonitor?.isConnected ?? false else {
            throw SupabaseError.offline
        }
        
        await MainActor.run {
            self.isUploading = true
        }
        
        defer {
            Task { @MainActor in
                self.isUploading = false
            }
        }
        
        let url = URL(string: AppConfig.rfidScansEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        for (key, value) in AppConfig.supabaseHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(tag)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorString = String(data: data, encoding: .utf8) {
                print("❌ Tag insert error: \(errorString)")
            }
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
        
        print("✅ Tag inserted: \(tag.rfidTag)")
    }
    
    func updateSession(id: UUID, status: ScanSession.SessionStatus, bottleCount: Int? = nil) async throws {
        guard networkMonitor?.isConnected ?? false else {
            throw SupabaseError.offline
        }
        
        let urlString = "\(AppConfig.scanSessionsEndpoint)?id=eq.\(id.uuidString)"
        let url = URL(string: urlString)!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        
        for (key, value) in AppConfig.supabaseHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        var payload: [String: Any] = [
            "status": status.rawValue
        ]
        
        if status == .stopped || status == .completed {
            payload["ended_at"] = ISO8601DateFormatter().string(from: Date())
        }
        
        if let count = bottleCount {
            payload["bottle_count"] = count
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorString = String(data: data, encoding: .utf8) {
                print("❌ Session update error: \(errorString)")
            }
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
        
        print("✅ Session updated: \(id)")
    }
    
    func batchInsertTags(_ tags: [RFIDTag]) async throws {
        guard !tags.isEmpty else { return }
        
        let batchSize = 50
        var successCount = 0
        
        for batchStart in stride(from: 0, to: tags.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, tags.count)
            let batch = Array(tags[batchStart..<batchEnd])
            
            for tag in batch {
                do {
                    try await insertTag(tag)
                    successCount += 1
                } catch {
                    print("❌ Batch insert failed for tag: \(tag.rfidTag)")
                    throw error
                }
            }
        }
        
        print("✅ Batch inserted \(successCount)/\(tags.count) tags")
    }
    
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
