//
//  LocationService.swift
//  LiquorRFIDBridge
//

import Foundation
import os.log

class LocationService: ObservableObject {
    static let shared = LocationService()
    
    @Published var locations: [Location] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var lastLoadedFromCacheAt: Date?
    @Published var lastFetchedAt: Date?
    
    private struct SlimLocation: Decodable {
        let id: String
        let name: String
        let code: String?
        let isActive: Bool?
        
        enum CodingKeys: String, CodingKey {
            case id
            case name
            case code
            case isActive = "is_active"
        }
    }
    
    private let logger = OSLog(subsystem: "com.liquorrfid.bridge", category: "locations")
    private let cacheURL: URL
    private let fileManager = FileManager.default
    
    private init() {
        let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        if !fileManager.fileExists(atPath: supportDir.path) {
            try? fileManager.createDirectory(at: supportDir, withIntermediateDirectories: true)
        }
        self.cacheURL = supportDir.appendingPathComponent("locations-cache.json")
        loadFromCache()
    }
    
    // Atomically start a fetch on the main actor; returns false if a fetch is already running
    @MainActor
    private func beginFetchIfNeeded() -> Bool {
        if isLoading { return false }
        isLoading = true
        errorMessage = nil
        return true
    }
    
    var activeLocations: [Location] {
        locations.filter { $0.isActive }
    }
    
    func fetchLocations() async {
        // Prevent duplicate concurrent fetches (debounce)
        let started = await beginFetchIfNeeded()
        if !started { return }
        
        // Explicitly select only the columns we decode (omit org if RLS hides it)
        let select = "select=id,name,code,is_active"
        let urlString = "\(AppConfig.locationsEndpoint)?\(select)&organization_id=eq.\(AppConfig.organizationId)&is_active=eq.true&order=name.asc"
        
        guard let url = URL(string: urlString) else {
            await MainActor.run {
                self.errorMessage = "Invalid URL"
                self.isLoading = false
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        for (key, value) in AppConfig.supabaseHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            
            do {
                // Decode a slim shape that matches the select list
                let slimDecoder = JSONDecoder()
                slimDecoder.keyDecodingStrategy = .useDefaultKeys
                let rows = try slimDecoder.decode([SlimLocation].self, from: data)
                let mapped = rows.map {
                    Location(
                        id: $0.id,
                        organizationId: nil,
                        name: $0.name,
                        code: $0.code,
                        description: nil,
                        isActive: $0.isActive ?? true,
                        settings: nil,
                        createdAt: nil
                    )
                }
                
                await MainActor.run {
                    self.locations = mapped
                    self.isLoading = false
                    self.lastFetchedAt = Date()
                    // Auto-clear invalid default after a successful fetch
                    if let savedId = AppPreferences.shared.defaultLocationId,
                       !self.activeLocations.contains(where: { $0.id == savedId }) {
                        AppPreferences.shared.defaultLocationId = nil
                    }
                }
                
                saveToCache(mapped)
            } catch {
                let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
                os_log("Decode error. Raw body: %{public}@", log: logger, type: .error, body)
                print("Decode error. Raw body: \(body)")
                throw error
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to fetch locations: \(error.localizedDescription)"
                self.isLoading = false
            }
            os_log("Location fetch error: %{public}@", log: logger, type: .error, error.localizedDescription)
        }
    }
    
    func refresh() async {
        await fetchLocations()
    }
    
    func getLocation(id: String) -> Location? {
        locations.first { $0.id == id }
    }
    
    // MARK: - Cache
    
    private func loadFromCache() {
        guard fileManager.fileExists(atPath: cacheURL.path) else { return }
        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let cached = try decoder.decode([Location].self, from: data)
            DispatchQueue.main.async {
                self.locations = cached
                self.lastLoadedFromCacheAt = Date()
            }
            // Reduced routine logging: keep errors only
        } catch {
            os_log("Failed to load locations cache: %{public}@", log: logger, type: .error, error.localizedDescription)
        }
    }
    
    private func saveToCache(_ locations: [Location]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(locations)
            try data.write(to: cacheURL, options: [.atomic])
            // Reduced routine logging: keep errors only
        } catch {
            os_log("Failed to save locations cache: %{public}@", log: logger, type: .error, error.localizedDescription)
        }
    }
}
