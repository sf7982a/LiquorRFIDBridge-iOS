//
  //  QueueService.swift
  //  LiquorRFIDBridge
  //
  //  Created on 2025-10-11
  //  Copyright © 2025 8Ball Inventory System. All rights reserved.
  //

  import Foundation
  import Combine
import UIKit
import os.log

/// Disk-backed queue for RFID tags with batching, backoff+jitter, and telemetry.
/// Depends on: RFIDTag, NetworkMonitor, AppConfig, SupabaseService, PersistentQueue
  class QueueService: ObservableObject {

    // MARK: - Published Properties (Telemetry)

      @Published var isProcessing: Bool = false
    @Published var queueDepth: Int = 0
    @Published var lastFlushAt: Date?
    @Published var lastFlushSucceeded: Int = 0
    @Published var lastFlushFailed: Int = 0

      // MARK: - Private Properties

    private let persistentStore = PersistentQueue()
    private let supabase = SupabaseService.shared
      private var networkMonitor: NetworkMonitor
      private var cancellables = Set<AnyCancellable>()
    private var flushTimerCancellable: AnyCancellable?
    private var bgCancellable: AnyCancellable?
    private var fgCancellable: AnyCancellable?
    private let logger = OSLog(subsystem: "com.liquorrfid.bridge", category: "queue")
    @Published var permanentFailureCount: Int = 0

      // MARK: - Computed Properties

      var queueCount: Int {
        queueDepth
      }

      var isFull: Bool {
        queueDepth >= AppConfig.maxQueueSize
      }

      // MARK: - Initialization

      init(networkMonitor: NetworkMonitor) {
          self.networkMonitor = networkMonitor
        
        // Update depth on init
        refreshDepth()

          // Auto-flush when connection restored
          networkMonitor.$isConnected
              .sink { [weak self] isConnected in
                guard let self else { return }
                  if isConnected {
                    Task { await self.flushQueue() }
                  }
              }
              .store(in: &cancellables)
        
        // Periodic flush while online
        startFlushTimer()
        
        // Pause/resume periodic flush on app background/foreground
        bgCancellable = NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.stopFlushTimer()
            }
        fgCancellable = NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.startFlushTimer()
                if self.networkMonitor.isConnected, self.queueDepth > 0 {
                    Task { await self.flushQueue() }
                }
            }
    }
    
    // MARK: - Public Methods
    
    /// Add a tag to the persistent queue
      func enqueue(tag: RFIDTag) {
          guard !isFull else {
              print("⚠️ Queue full, dropping tag: \(tag.rfidTag)")
              return
          }
        // Encode tag as JSON (snake_case keys)
        let dict = tag.toDictionary()
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let json = String(data: data, encoding: .utf8) else {
            print("❌ Failed to encode tag for queue")
            return
        }
        persistentStore.enqueue(
            payloadJSON: json,
            organizationId: tag.organizationId,
            sessionId: tag.sessionId?.uuidString,
            endpoint: AppConfig.fnBatchInsertScans,
            scheduleAt: Date()
        )
        refreshDepth()
          print("📥 Queued tag: \(tag.rfidTag) (Queue: \(queueCount))")
      }

    /// Manually trigger a flush attempt
      func flushQueue() async {
        guard AppConfig.uploadEnabled else { return }
          guard networkMonitor.isConnected else { return }
        if isProcessing { return }
        
        await MainActor.run { self.isProcessing = true }
        defer { Task { @MainActor in self.isProcessing = false } }
        
        var totalSucceeded = 0
        var totalFailed = 0
        
        let readyFetchLimit = max(AppConfig.queueBatchSize * 5, 500)
        let maxAttempts = AppConfig.maxUploadAttempts
        
        while true {
            let ready = persistentStore.fetchReady(limit: readyFetchLimit, now: Date(), maxAttempts: maxAttempts)
            if ready.isEmpty { break }
            
            // Decode and group by (org, session)
            struct Key: Hashable { let org: String; let session: String? }
            var groups: [Key: [(PersistentQueue.Item, RFIDTag)]] = [:]
            
            for item in ready {
                guard let data = item.payloadJSON.data(using: .utf8) else { continue }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let tag = try? decoder.decode(RFIDTag.self, from: data) {
                    let key = Key(org: item.organizationId, session: item.sessionId)
                    groups[key, default: []].append((item, tag))
                } else {
                    // Malformed payload — drop it
                    persistentStore.delete(ids: [item.rowId])
                }
            }
            
            // Upload per group in chunks
            for (_, tuples) in groups {
                // Preserve original order (already by created_at asc)
                var chunk: [(PersistentQueue.Item, RFIDTag)] = []
                for pair in tuples {
                    chunk.append(pair)
                    if chunk.count == min(AppConfig.queueBatchSize, 100) {
                        await handleChunkUpload(chunk: chunk, totalSucceeded: &totalSucceeded, totalFailed: &totalFailed)
                        chunk.removeAll(keepingCapacity: true)
                    }
                }
                if !chunk.isEmpty {
                    await handleChunkUpload(chunk: chunk, totalSucceeded: &totalSucceeded, totalFailed: &totalFailed)
                }
            }
            
            refreshDepth()
            if !networkMonitor.isConnected { break }
            // If fewer than fetch limit were ready, take a short breath to avoid tight loop
            if ready.count < readyFetchLimit { break }
              }
        
        await MainActor.run {
            self.lastFlushAt = Date()
            self.lastFlushSucceeded = totalSucceeded
            self.lastFlushFailed = totalFailed
          }
        
        // Reduce routine noise: only log when work happened or failures occurred
        if totalSucceeded > 0 || totalFailed > 0 {
            print("📤 Flush complete — succeeded: \(totalSucceeded), failed: \(totalFailed), remaining: \(queueCount)")
        }
      }

    /// Clear all queued items (dev/testing)
      func clearQueue() {
        // Delete everything by fetching and deleting
        let all = persistentStore.fetchReady(limit: Int.max, now: Date().addingTimeInterval(10_000_000), maxAttempts: Int.max)
        persistentStore.delete(ids: all.map { $0.rowId })
        refreshDepth()
          print("🗑️ Queue cleared")
      }

    // MARK: - Private Helpers
    
    private func handleChunkUpload(chunk: [(PersistentQueue.Item, RFIDTag)],
                                   totalSucceeded: inout Int,
                                   totalFailed: inout Int) async {
        let ids = chunk.map { $0.0.rowId }
        let attemptCounts = chunk.map { $0.0.attemptCount }
        let tags = chunk.map { $0.1 }
        do {
            try await supabase.batchInsertTags(tags)
            persistentStore.delete(ids: ids)
            totalSucceeded += tags.count
        } catch {
            // Split into items that will hit/exceed max attempts vs ones that will retry
            var toDelete: [Int64] = []
            var toUpdate: [Int64] = []
            let maxAttempts = AppConfig.maxUploadAttempts
            
            for (idx, rowId) in ids.enumerated() {
                let nextAttempt = attemptCounts[idx] + 1
                if nextAttempt >= maxAttempts {
                    toDelete.append(rowId)
                } else {
                    toUpdate.append(rowId)
                }
            }
            
            // Delete permanent failures with critical log
            if !toDelete.isEmpty {
                persistentStore.delete(ids: toDelete)
                let failedTags = chunk.enumerated().compactMap { (idx, pair) -> RFIDTag? in
                    let id = pair.0.rowId
                    return toDelete.contains(id) ? pair.1 : nil
                }
                for (idx, tag) in failedTags.enumerated() {
                    let attempts = attemptCounts[idx] + 1
                    os_log("CRITICAL: Tag permanently failed after %d attempts. ID: %{public}@, Error: %{public}@, Queue depth: %d",
                           log: logger, type: .error,
                           attempts, tag.id.uuidString, error.localizedDescription, self.queueDepth)
                }
                await MainActor.run {
                    self.permanentFailureCount += toDelete.count
                }
            }
            
            // Mark remaining as failed with backoff
            let maxAttempt = (attemptCounts.max() ?? 0)
            let delaySeconds = nextBackoffSeconds(attempt: maxAttempt)
            if !toUpdate.isEmpty {
                let nextAt = Date().addingTimeInterval(delaySeconds)
                persistentStore.markFailed(ids: toUpdate, error: error.localizedDescription, nextAttemptAt: nextAt)
            }
            totalFailed += tags.count
            print("❌ Chunk upload failed (\(tags.count) items): \(error.localizedDescription). Next attempt in \(Int(delaySeconds))s")
        }
    }
    
    private func nextBackoffSeconds(attempt: Int) -> TimeInterval {
        let base = AppConfig.backoffBaseSeconds
        let maxS = AppConfig.backoffMaxSeconds
        let raw = min(maxS, base * pow(2.0, Double(max(0, attempt))))
        let jitter = raw * AppConfig.backoffJitterRatio
        let jittered = raw + Double.random(in: -jitter...jitter)
        return max(1.0, jittered)
    }
    
    private func refreshDepth() {
        let count = persistentStore.countAll()
        DispatchQueue.main.async {
            self.queueDepth = count
        }
    }
    
    private func startFlushTimer() {
        stopFlushTimer()
        flushTimerCancellable = Timer
            .publish(every: AppConfig.flushIntervalSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard AppConfig.uploadEnabled, self.networkMonitor.isConnected else { return }
                if self.queueDepth > 0, !self.isProcessing {
                    Task { await self.flushQueue() }
                }
            }
    }
    
    private func stopFlushTimer() {
        flushTimerCancellable?.cancel()
        flushTimerCancellable = nil
      }
  }
