//
  //  RFIDTag.swift
  //  LiquorRFIDBridge
  //
  //  Created on 2025-10-11
  //  Copyright © 2025 8Ball Inventory System. All rights reserved.
  //

  import Foundation

  /// Represents a single RFID tag read from the RFD40 reader
  struct RFIDTag: Identifiable, Codable, Equatable {

      // MARK: - Properties

      /// Unique identifier for this tag read
      let id: UUID

      /// Organization UUID from AppConfig
      let organizationId: String

      /// Optional scan session identifier (assigned when session created)
      var sessionId: UUID?

      /// Optional location identifier (assigned from settings)
      var locationId: String?

      /// EPC tag ID from reader (e.g., "E280689400004006A12BC123")
      let rfidTag: String

      /// Signal strength in dBm (typically -90 to -30)
      let rssi: Int

      /// When tag was read
      let timestamp: Date

      /// Whether web app has handled this tag
      var processed: Bool

      /// Additional information about the tag read
      var metadata: [String: String]

      // MARK: - Initialization

      init(
          id: UUID = UUID(),
          organizationId: String,
          sessionId: UUID? = nil,
          locationId: String? = nil,
          rfidTag: String,
          rssi: Int,
          timestamp: Date = Date(),
          processed: Bool = false,
          metadata: [String: String] = [:]
      ) {
          self.id = id
          self.organizationId = organizationId
          self.sessionId = sessionId
          self.locationId = locationId
          self.rfidTag = rfidTag
          self.rssi = rssi
          self.timestamp = timestamp
          self.processed = processed
          self.metadata = metadata
      }

      // MARK: - Computed Properties

      /// Returns true if signal strength is strong (> -50 dBm)
      var isStrongSignal: Bool {
          rssi > -50
      }

      /// Returns timestamp formatted as "HH:mm:ss"
      var formattedTimestamp: String {
          let formatter = DateFormatter()
          formatter.dateFormat = "HH:mm:ss"
          return formatter.string(from: timestamp)
      }

      // MARK: - Methods

      /// Converts tag to dictionary for JSON encoding
      /// Used when POSTing to Supabase
      func toDictionary() -> [String: Any] {
          var dict: [String: Any] = [
              "id": id.uuidString,
              "organization_id": organizationId,
              "rfid_tag": rfidTag,
              "rssi": rssi,
              "timestamp": ISO8601DateFormatter().string(from: timestamp),
              "processed": processed,
              "metadata": metadata
          ]

          // Only include optional values if not nil
          if let sessionId = sessionId {
              dict["session_id"] = sessionId.uuidString
          }

          if let locationId = locationId {
              dict["location_id"] = locationId
          }

          return dict
      }

      // MARK: - Coding Keys

      enum CodingKeys: String, CodingKey {
          case id
          case organizationId = "organization_id"
          case sessionId = "session_id"
          case locationId = "location_id"
          case rfidTag = "rfid_tag"
          case rssi
          case timestamp
          case processed
          case metadata
      }
  }
