//
  //  QueueService.swift
  //  LiquorRFIDBridge
  //
  //  Created on 2025-10-11
  //  Copyright © 2025 8Ball Inventory System. All rights reserved.
  //

  import Foundation
  import Combine

  /// Queue RFID tags when offline, flush when online
  /// Depends on: RFIDTag model, NetworkMonitor, AppConfig
  class QueueService: ObservableObject {

      // MARK: - Published Properties

      @Published var queuedTags: [RFIDTag] = []
      @Published var isProcessing: Bool = false

      // MARK: - Private Properties

      private var networkMonitor: NetworkMonitor
      private var cancellables = Set<AnyCancellable>()

      // MARK: - Computed Properties

      var queueCount: Int {
          queuedTags.count
      }

      var isFull: Bool {
          queuedTags.count >= AppConfig.maxQueueSize
      }

      // MARK: - Initialization

      init(networkMonitor: NetworkMonitor) {
          self.networkMonitor = networkMonitor

          // Auto-flush when connection restored
          networkMonitor.$isConnected
              .sink { [weak self] isConnected in
                  if isConnected {
                      Task {
                          await self?.flushQueue()
                      }
                  }
              }
              .store(in: &cancellables)
      }

      // MARK: - Methods

      /// Add a tag to the queue when offline or upload fails
      func enqueue(tag: RFIDTag) {
          guard !isFull else {
              print("⚠️ Queue full, dropping tag: \(tag.rfidTag)")
              return
          }

          DispatchQueue.main.async {
              self.queuedTags.append(tag)
          }

          print("📥 Queued tag: \(tag.rfidTag) (Queue: \(queueCount))")
      }

      /// Flush queued tags to Supabase when connection is available
      func flushQueue() async {
          guard !queuedTags.isEmpty else { return }
          guard networkMonitor.isConnected else { return }

          DispatchQueue.main.async {
              self.isProcessing = true
          }

          print("📤 Flushing queue: \(queueCount) tags")

          // Process in batches of 50
          let batchSize = 50
          var processedCount = 0

          while !queuedTags.isEmpty && networkMonitor.isConnected {
              let batch = Array(queuedTags.prefix(batchSize))

              for tag in batch {
                  do {
                      // Note: Will use SupabaseService.shared.insertTag(tag) when implemented
                      // For now, just simulate success
                      try await Task.sleep(nanoseconds: 100_000_000) // 0.1 sec delay

                      DispatchQueue.main.async {
                          self.queuedTags.removeAll { $0.id == tag.id }
                      }

                      processedCount += 1
                  } catch {
                      print("❌ Failed to flush tag: \(error.localizedDescription)")
                      break // Stop on first error, will retry later
                  }
              }
          }

          DispatchQueue.main.async {
              self.isProcessing = false
          }

          print("✅ Flushed \(processedCount) tags, \(queueCount) remaining")
      }

      /// Clear all queued tags (for testing/reset)
      func clearQueue() {
          DispatchQueue.main.async {
              self.queuedTags.removeAll()
          }
          print("🗑️ Queue cleared")
      }

      /// Retry uploading a tag with exponential backoff
      func retryTag(_ tag: RFIDTag, attempt: Int) async {
          guard attempt < AppConfig.maxRetryAttempts else {
              print("❌ Max retries reached for tag: \(tag.rfidTag)")
              enqueue(tag: tag) // Add to queue for later
              return
          }

          print("🔄 Retry attempt \(attempt + 1) for tag: \(tag.rfidTag)")

          try? await Task.sleep(nanoseconds: UInt64(AppConfig.retryDelay * 1_000_000_000))

          // Will retry via SupabaseService when implemented
      }
  }
