//
  //  NetworkMonitor.swift
  //  LiquorRFIDBridge
  //
  //  Created on 2025-10-11
  //  Copyright © 2025 8Ball Inventory System. All rights reserved.
  //

  import Foundation
  import Network
  import Combine

  /// Monitor internet connectivity status (WiFi/Cellular/Offline)
  /// Used by SupabaseService and QueueService to determine when to retry uploads
  class NetworkMonitor: ObservableObject {

      // MARK: - Published Properties

      @Published var isConnected: Bool = false
      @Published var connectionType: ConnectionType = .unknown

      // MARK: - Private Properties

      private let monitor: NWPathMonitor
      private let queue = DispatchQueue(label: "NetworkMonitor")

      // MARK: - Initialization

      init() {
          monitor = NWPathMonitor()

          monitor.pathUpdateHandler = { [weak self] path in
              DispatchQueue.main.async {
                  self?.isConnected = path.status == .satisfied

                  if path.usesInterfaceType(.wifi) {
                      self?.connectionType = .wifi
                  } else if path.usesInterfaceType(.cellular) {
                      self?.connectionType = .cellular
                  } else if path.usesInterfaceType(.wiredEthernet) {
                      self?.connectionType = .wired
                  } else {
                      self?.connectionType = .unknown
                  }
              }
          }

          monitor.start(queue: queue)
      }

      // MARK: - Deinitialization

      deinit {
          monitor.cancel()
      }

      // MARK: - Methods

      /// Force immediate path check for manual connectivity verification
      func checkConnection() {
          // Force immediate path check using current path status
          let path = monitor.currentPath
          DispatchQueue.main.async {
              self.isConnected = path.status == .satisfied
              
              if path.usesInterfaceType(.wifi) {
                  self.connectionType = .wifi
              } else if path.usesInterfaceType(.cellular) {
                  self.connectionType = .cellular
              } else if path.usesInterfaceType(.wiredEthernet) {
                  self.connectionType = .wired
              } else {
                  self.connectionType = .unknown
              }
          }
      }

      // MARK: - Enums

      enum ConnectionType {
          case wifi
          case cellular
          case wired      // For future iPad with ethernet adapter
          case unknown

          var description: String {
              switch self {
              case .wifi: return "WiFi"
              case .cellular: return "Cellular"
              case .wired: return "Wired"
              case .unknown: return "No Connection"
              }
          }
      }
  }
