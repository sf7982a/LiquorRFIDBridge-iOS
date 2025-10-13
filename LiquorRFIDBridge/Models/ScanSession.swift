//
//  ScanSession.swift
//  LiquorRFIDBridge
//
//  Created on 2025-10-11
//  Copyright © 2025 8Ball Inventory System. All rights reserved.
//

import Foundation

/// Represents a scanning session created by the bridge app
struct ScanSession: Identifiable, Codable, Equatable {

    // MARK: - Properties

    /// Unique session identifier
    let id: UUID

    /// Organization UUID from AppConfig
    let organizationId: String

    /// Selected location for this session
    var locationId: String?

    /// User ID who started the session (maps to started_by in DB)
    var startedBy: String?

    /// Type of scanning session
    let sessionType: SessionType

    /// Device name running this bridge
    let deviceName: String

    /// When session was started
    let startedAt: Date

    /// When session was ended (maps to ended_at in DB)
    var endedAt: Date?

    /// Current status of the session
    var status: SessionStatus

    /// Number of bottles scanned in this session
    var bottleCount: Int

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        organizationId: String,
        locationId: String? = nil,
        userId: String? = nil,
        sessionType: SessionType,
        deviceName: String = AppConfig.deviceName,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        status: SessionStatus,
        bottleCount: Int = 0
    ) {
        self.id = id
        self.organizationId = organizationId
        self.locationId = locationId
        self.startedBy = userId  // Map userId parameter to startedBy property
        self.sessionType = sessionType
        self.deviceName = deviceName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.bottleCount = bottleCount
    }

    // MARK: - Computed Properties

    /// Auto-generated display name like "Input Session - 3:45 PM"
    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let time = formatter.string(from: startedAt)
        return "\(sessionType.rawValue.capitalized) Session - \(time)"
    }

    /// Returns time difference between start and end (or now if active)
    var duration: TimeInterval? {
        let endTime = endedAt ?? Date()
        return endTime.timeIntervalSince(startedAt)
    }

    /// Returns duration formatted as "MM:SS"
    var formattedDuration: String {
        guard let duration = duration else {
            return "00:00"
        }

        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Enums

    enum SessionType: String, Codable {
        case input = "input"       // Adding new inventory
        case output = "output"     // Removing/transferring inventory
        case inventory = "inventory" // Counting/auditing existing inventory
    }

    enum SessionStatus: String, Codable {
        case active = "active"
        case stopped = "stopped"
        case completed = "completed"
    }

    // MARK: - Coding Keys (Maps Swift properties to database columns)

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case locationId = "location_id"
        case startedBy = "started_by"        // Maps to DB column
        case sessionType = "session_type"
        case deviceName = "device_name"
        case startedAt = "started_at"
        case endedAt = "ended_at"            // Maps to DB column
        case status
        case bottleCount = "bottle_count"
    }
}
