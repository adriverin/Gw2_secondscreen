import Foundation

enum EarlyBeta {
    static let developerModeKey = "developer.mode.enabled"

    static func qaToolsVisible(developerMode: Bool) -> Bool { developerMode }

    static var allowsFixtureData: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    static var allowsTileDebugGrid: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    static func allowsTelemetrySimulation(developerMode: Bool) -> Bool {
#if DEBUG
        return true
#else
        return developerMode
#endif
    }
}

enum TelemetryPublishAudit {
    /// Bridge shared-memory sample rate.
    static let bridgeSampleHertz = 25
    /// Bridge WebSocket publication of the latest sample.
    static let bridgePublishHertz = 20
    /// iOS keeps only the newest envelope (`bufferingNewest(1)`).
    static let swiftLatestOnly = true
    /// Player marker interpolation window. Not a second publication clock.
    static let mapMarkerSeconds = 0.04
    /// Navigation sorting is independent and slower than telemetry.
    static let navigationMinimumInterval = 0.25
    static let navigationMinimumMovement = 4.0

    static var summary: String {
        """
        Bridge sample \(bridgeSampleHertz) Hz
        Bridge publish ~\(bridgePublishHertz) Hz
        Swift publication: latest envelope only
        Map marker interpolation \(mapMarkerSeconds)s
        Navigation recompute ≥ \(navigationMinimumInterval)s or \(navigationMinimumMovement) units
        Rates are not required to be identical. Smooth motion is preserved; proximity work is throttled.
        """
    }
}
