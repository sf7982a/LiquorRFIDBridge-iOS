//
  //  Location.swift
  //  LiquorRFIDBridge
  //
  //  Created on 2025-10-11
  //  Copyright © 2025 8Ball Inventory System. All rights reserved.
  //

  import Foundation

    /// Represents a physical location (bar, warehouse, etc.) from Supabase
  struct Location: Identifiable, Codable, Equatable, Hashable {

      // MARK: - Properties

      /// Unique location identifier (UUID as string from Supabase)
      let id: String

      /// Organization UUID this location belongs to
        let organizationId: String?

      /// Location name (e.g., "Main Bar", "Back Warehouse")
      let name: String

      /// Optional short code (e.g., "MB", "BW")
      let code: String?

      /// Optional description of the location
      let description: String?

      /// Whether this location is currently active
      let isActive: Bool

      /// Additional location settings from JSONB field
        let settings: [String: String]?

      /// When location was created
        let createdAt: Date?

      // MARK: - Initialization

      init(
          id: String,
            organizationId: String? = nil,
          name: String,
          code: String? = nil,
          description: String? = nil,
          isActive: Bool = true,
            settings: [String: String]? = nil,
            createdAt: Date? = nil
      ) {
          self.id = id
          self.organizationId = organizationId
          self.name = name
          self.code = code
          self.description = description
          self.isActive = isActive
          self.settings = settings
          self.createdAt = createdAt
      }

      // MARK: - Computed Properties

      /// Returns formatted display name with code if available
      /// Example: "Main Bar (MB)" or "Main Bar"
      var displayName: String {
          if let code = code {
              return "\(name) (\(code))"
          }
          return name
      }

      // MARK: - Hashable Conformance

      func hash(into hasher: inout Hasher) {
          hasher.combine(id)
      }

      // MARK: - Coding Keys

      enum CodingKeys: String, CodingKey {
          case id
          case organizationId = "organization_id"
          case name
          case code
          case description
          case isActive = "is_active"
          case settings
          case createdAt = "created_at"
      }
  }
