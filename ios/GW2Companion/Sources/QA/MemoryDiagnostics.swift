import Foundation
import os

struct MemoryDiagnosticsSnapshot: Codable, Equatable, Sendable {
    var tileCacheCount: Int
    var imageMemoryCacheCount: Int
    var mapIconCount: Int
    var activeMapMarkers: Int
    var activeObjectives: Int
    var telemetryPacketsPerSecond: Int
    var availableMemoryBytes: UInt64?
}

enum ProcessMemoryDiagnostics {
    static func availableBytes() -> UInt64? {
        let value = os_proc_available_memory()
        return value > 0 ? UInt64(value) : nil
    }
}

@MainActor
enum MemoryDiagnostics {
    static func snapshot(
        telemetryPacketsPerSecond: Int,
        activeMapMarkers: Int,
        activeObjectives: Int
    ) -> MemoryDiagnosticsSnapshot {
        MemoryDiagnosticsSnapshot(
            tileCacheCount: MapTileImageCache.shared.memoryCount,
            imageMemoryCacheCount: RemoteImagePipeline.shared.memoryCount,
            mapIconCount: MapIconStore.shared.loadedImageCount,
            activeMapMarkers: activeMapMarkers,
            activeObjectives: activeObjectives,
            telemetryPacketsPerSecond: telemetryPacketsPerSecond,
            availableMemoryBytes: ProcessMemoryDiagnostics.availableBytes())
    }
}
