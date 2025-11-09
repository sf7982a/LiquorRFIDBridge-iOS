//
//  AppPreferences.swift
//  LiquorRFIDBridge
//
//  Centralized runtime preferences with UserDefaults persistence
//

import Foundation
import Combine

class AppPreferences: ObservableObject {
    static let shared = AppPreferences()
    
    // Keys
    private let kUniquePerSession = "prefs.uniquePerSession"
    private let kMinAcceptedRSSI = "prefs.minAcceptedRSSI"
    private let kTriggerScanning  = "prefs.triggerScanning"
    
    @Published var uniquePerSession: Bool {
        didSet { UserDefaults.standard.set(uniquePerSession, forKey: kUniquePerSession) }
    }
    
    // Store as Int, use nil to represent disabled
    @Published var minAcceptedRSSI: Int? {
        didSet { UserDefaults.standard.set(minAcceptedRSSI, forKey: kMinAcceptedRSSI) }
    }
    
    @Published var triggerScanning: Bool {
        didSet { UserDefaults.standard.set(triggerScanning, forKey: kTriggerScanning) }
    }
    
    private init() {
        let defaults = UserDefaults.standard
        // Defaults align with existing behavior
        if defaults.object(forKey: kUniquePerSession) == nil {
            defaults.set(true, forKey: kUniquePerSession)
        }
        if defaults.object(forKey: kTriggerScanning) == nil {
            defaults.set(false, forKey: kTriggerScanning)
        }
        self.uniquePerSession = defaults.bool(forKey: kUniquePerSession)
        self.minAcceptedRSSI = defaults.object(forKey: kMinAcceptedRSSI) as? Int
        self.triggerScanning = defaults.bool(forKey: kTriggerScanning)
    }
}

