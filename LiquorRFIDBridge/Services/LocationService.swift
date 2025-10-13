//
//  LocationService.swift
//  LiquorRFIDBridge
//

import Foundation

class LocationService: ObservableObject {
    static let shared = LocationService()
    
    @Published var locations: [Location] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private init() {}
    
    var activeLocations: [Location] {
        locations.filter { $0.isActive }
    }
    
    func fetchLocations() async {
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        let urlString = "\(AppConfig.locationsEndpoint)?organization_id=eq.\(AppConfig.organizationId)&is_active=eq.true&order=name.asc"
        
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
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let fetchedLocations = try decoder.decode([Location].self, from: data)
            
            await MainActor.run {
                self.locations = fetchedLocations
                self.isLoading = false
            }
            
            print("✅ Fetched \(fetchedLocations.count) locations")
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to fetch locations: \(error.localizedDescription)"
                self.isLoading = false
            }
            print("❌ Location fetch error: \(error)")
        }
    }
    
    func refresh() async {
        await fetchLocations()
    }
    
    func getLocation(id: String) -> Location? {
        locations.first { $0.id == id }
    }
}
