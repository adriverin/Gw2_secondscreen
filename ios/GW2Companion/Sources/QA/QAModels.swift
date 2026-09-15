import Foundation

enum QAResultState: String, Codable, CaseIterable, Sendable {
    case notTested
    case passed
    case failed

    var title: String {
        switch self {
        case .notTested: "Not Tested"
        case .passed: "Pass"
        case .failed: "Fail"
        }
    }

    var symbol: String {
        switch self {
        case .notTested: "circle"
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }
}

enum QASeverity: String, Codable, CaseIterable, Sendable, Identifiable {
    case p0, p1, p2, p3
    var id: String { rawValue }

    var title: String {
        switch self {
        case .p0: "P0"
        case .p1: "P1"
        case .p2: "P2"
        case .p3: "P3"
        }
    }

    var summary: String {
        switch self {
        case .p0: "Data loss, crash, wrong map, cannot connect, or security issue"
        case .p1: "Major feature unusable"
        case .p2: "Usability issue with workaround"
        case .p3: "Cosmetic or minor"
        }
    }
}

struct QACheckResult: Codable, Equatable, Sendable, Identifiable {
    let id: String
    var state: QAResultState
    var note: String?
    var testedAt: Date?
    var severity: QASeverity?

    init(
        id: String,
        state: QAResultState = .notTested,
        note: String? = nil,
        testedAt: Date? = nil,
        severity: QASeverity? = nil
    ) {
        self.id = id
        self.state = state
        self.note = note
        self.testedAt = testedAt
        self.severity = severity
    }
}

enum QACheckGroup: String, Codable, CaseIterable, Sendable, Identifiable {
    case pcConnection
    case mumbleLink
    case mapAlignment
    case mapTransition
    case account
    case today
    case resilience
    case session

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pcConnection: "PC Connection"
        case .mumbleLink: "MumbleLink"
        case .mapAlignment: "Map Alignment"
        case .mapTransition: "Map Transition"
        case .account: "Account"
        case .today: "Today"
        case .resilience: "Resilience"
        case .session: "Session"
        }
    }
}

struct QACheckDefinition: Equatable, Sendable, Identifiable {
    let id: String
    let group: QACheckGroup
    let title: String
    let requiredAction: String
    let expected: String
}

enum QACatalog {
    static let reportSchemaVersion = 1

    static let checks: [QACheckDefinition] = [
        QACheckDefinition(
            id: "pc.qrPairing", group: .pcConnection, title: "QR pairing",
            requiredAction: "Scan the current bridge QR code on a physical iPhone.",
            expected: "The device pairs and stores the PC address without exposing the token in UI logs."),
        QACheckDefinition(
            id: "pc.lanConnection", group: .pcConnection, title: "LAN connection",
            requiredAction: "Keep the iPhone and Windows PC on the same trusted home Wi-Fi.",
            expected: "Connection reaches Connected to PC / LIVE without a public-network firewall exception."),
        QACheckDefinition(
            id: "pc.reconnectAfterBridgeRestart", group: .pcConnection, title: "Reconnect after bridge restart",
            requiredAction: "Follow the guided bridge-restart steps. Do not auto-pass.",
            expected: "LIVE returns after the bridge process is closed and started again."),

        QACheckDefinition(
            id: "mumble.character", group: .mumbleLink, title: "Character",
            requiredAction: "Enter a character in Guild Wars 2 and compare the QA MumbleLink card.",
            expected: "The live character identity updates. Names stay redacted in exports."),
        QACheckDefinition(
            id: "mumble.mapId", group: .mumbleLink, title: "Map ID",
            requiredAction: "Stand in a known map and confirm the numeric map ID.",
            expected: "Map ID matches the actual GW2 map."),
        QACheckDefinition(
            id: "mumble.movement", group: .mumbleLink, title: "Movement",
            requiredAction: "Walk in a straight line and watch player X/Y.",
            expected: "Coordinates change smoothly without implausible jumps."),
        QACheckDefinition(
            id: "mumble.heading", group: .mumbleLink, title: "Heading",
            requiredAction: "Turn in place and watch the player marker / avatar front.",
            expected: "Heading follows the character."),
        QACheckDefinition(
            id: "mumble.mount", group: .mumbleLink, title: "Mount",
            requiredAction: "Mount and dismount.",
            expected: "Mount index changes in the live MumbleLink card."),
        QACheckDefinition(
            id: "mumble.combat", group: .mumbleLink, title: "Combat",
            requiredAction: "Enter and leave combat.",
            expected: "Combat flag changes in the live MumbleLink card."),

        QACheckDefinition(
            id: "map.coreTyriaWaypoint", group: .mapAlignment, title: "Core Tyria waypoint",
            requiredAction: "Stand on a Core Tyria waypoint, select it in Map Alignment, and judge overlap.",
            expected: "Player marker visually overlaps the waypoint. No hidden offset is applied."),
        QACheckDefinition(
            id: "map.poi", group: .mapAlignment, title: "POI",
            requiredAction: "Stand on an official POI and compare player vs POI coordinates.",
            expected: "Delta/distance are small and the marker overlaps the POI artwork."),
        QACheckDefinition(
            id: "map.edge", group: .mapAlignment, title: "Map edge",
            requiredAction: "Stand at a visible map edge and compare overlay vs artwork.",
            expected: "The edge of the painted map matches overlay space. If artwork is missing, record that separately."),
        QACheckDefinition(
            id: "map.expansionArtwork", group: .mapAlignment, title: "Expansion map if artwork exists",
            requiredAction: "Visit an expansion map. Confirm whether official tiles exist, then check overlap.",
            expected: "Missing official artwork is reported as coverage, not as a wrong-map bug."),

        QACheckDefinition(
            id: "mapTransition.mapId", group: .mapTransition, title: "Map ID after transition",
            requiredAction: "Travel Core map A → portal/waypoint → map B.",
            expected: "Map ID updates to map B."),
        QACheckDefinition(
            id: "mapTransition.mapName", group: .mapTransition, title: "Map name after transition",
            requiredAction: "Confirm the displayed map name after the transition.",
            expected: "Name matches map B."),
        QACheckDefinition(
            id: "mapTransition.tileArtwork", group: .mapTransition, title: "Tile artwork after transition",
            requiredAction: "Confirm tiles reload for map B or coverage explains missing paint.",
            expected: "New map tiles load, or QA reports official artwork unavailable."),
        QACheckDefinition(
            id: "mapTransition.pois", group: .mapTransition, title: "POIs after transition",
            requiredAction: "Confirm official POIs belong to map B.",
            expected: "Old-map POIs are gone."),
        QACheckDefinition(
            id: "mapTransition.playerMarker", group: .mapTransition, title: "Player marker after transition",
            requiredAction: "Confirm the player marker sits on map B.",
            expected: "Marker is not stuck on map A."),
        QACheckDefinition(
            id: "mapTransition.gathering", group: .mapTransition, title: "Gathering markers after transition",
            requiredAction: "Confirm gathering markers match map B coverage.",
            expected: "Previous map gathering is cleared."),
        QACheckDefinition(
            id: "mapTransition.currentTarget", group: .mapTransition, title: "Current target after transition",
            requiredAction: "If a target was set, confirm it is replaced or cleared honestly.",
            expected: "Stale targets from map A do not complete the route."),
        QACheckDefinition(
            id: "mapTransition.route", group: .mapTransition, title: "Route handling after transition",
            requiredAction: "Start a route, change maps, and observe route handling.",
            expected: "Route does not complete from stale telemetry."),

        QACheckDefinition(
            id: "account.characters", group: .account, title: "Characters",
            requiredAction: "Open Characters and compare the roster to the game.",
            expected: "Real account characters load. Missing characters permission is explicit."),
        QACheckDefinition(
            id: "account.bank", group: .account, title: "Bank",
            requiredAction: "Open Bank and compare occupied slots to the in-game bank.",
            expected: "Bank shows live or clearly labeled cached data."),
        QACheckDefinition(
            id: "account.materials", group: .account, title: "Materials",
            requiredAction: "Open Materials and compare one stack to the game.",
            expected: "Quantities match after a live refresh."),
        QACheckDefinition(
            id: "account.shared", group: .account, title: "Shared inventory",
            requiredAction: "Open Shared Inventory and compare slots to the game.",
            expected: "Shared slots match the account."),
        QACheckDefinition(
            id: "account.inventoryRefresh", group: .account, title: "Inventory refresh verification",
            requiredAction: "Note a material quantity, change it in game, refresh Companion, compare again.",
            expected: "The refreshed quantity matches the game. Timing is not inferred automatically."),

        QACheckDefinition(
            id: "today.vault", group: .today, title: "Wizard's Vault",
            requiredAction: "Compare Vault daily/weekly/special progress to the game.",
            expected: "Progress and claimable state match the account."),
        QACheckDefinition(
            id: "today.daily", group: .today, title: "Daily progress",
            requiredAction: "Compare daily Vault objectives to the game.",
            expected: "Completed/incomplete state matches."),
        QACheckDefinition(
            id: "today.weekly", group: .today, title: "Weekly progress",
            requiredAction: "Compare weekly Vault objectives to the game.",
            expected: "Completed/incomplete state matches."),
        QACheckDefinition(
            id: "today.claimed", group: .today, title: "Claimed state",
            requiredAction: "Confirm claimed vs ready-to-claim vs incomplete.",
            expected: "Companion does not invent claim state."),
        QACheckDefinition(
            id: "today.worldBosses", group: .today, title: "World bosses",
            requiredAction: "Compare account world-boss checklist to the game.",
            expected: "IDs and completion match. This is not an event schedule."),
        QACheckDefinition(
            id: "today.crafting", group: .today, title: "Daily crafting",
            requiredAction: "Compare daily crafting completions to the game.",
            expected: "Completed crafts match."),
        QACheckDefinition(
            id: "today.raids", group: .today, title: "Raids",
            requiredAction: "Compare raid encounter completions to the game.",
            expected: "Checkpoints are not counted as bosses."),
        QACheckDefinition(
            id: "today.dungeons", group: .today, title: "Dungeons",
            requiredAction: "Compare dungeon path completions to the game.",
            expected: "Paths merge correctly."),

        QACheckDefinition(
            id: "resilience.bridgeRestart", group: .resilience, title: "Bridge restart",
            requiredAction: "Confirm LIVE, close the bridge, wait for Reconnecting, restart the bridge, confirm LIVE.",
            expected: "LIVE returns. Record event-log timestamps. Do not auto-pass."),
        QACheckDefinition(
            id: "resilience.gw2Restart", group: .resilience, title: "GW2 restart",
            requiredAction: "Confirm LIVE, close GW2, confirm GW2 not running, launch GW2, enter a character, confirm LIVE.",
            expected: "The app recovers without a reinstall."),
        QACheckDefinition(
            id: "resilience.wifi", group: .resilience, title: "Wi-Fi interruption",
            requiredAction: "Confirm LIVE, disable iPhone Wi-Fi, wait, re-enable, confirm automatic reconnect.",
            expected: "The app reconnects on its own. The tester controls Wi-Fi; the app does not."),
        QACheckDefinition(
            id: "resilience.background", group: .resilience, title: "Background / foreground",
            requiredAction: "Confirm LIVE, background for 30 seconds, return, confirm connection and map/session remain intact.",
            expected: "Foreground restore is prompt and does not duplicate sockets."),
        QACheckDefinition(
            id: "resilience.forceQuit", group: .resilience, title: "Force-quit restoration",
            requiredAction: "Start a session, lock one task, skip one task, force quit, relaunch.",
            expected: "Session, locked, and skipped tasks restore. Navigation waits for fresh telemetry. PC reconnects."),
        QACheckDefinition(
            id: "resilience.characterSwitch", group: .resilience, title: "Character switch",
            requiredAction: "Play character A, verify profile match, return to character select, enter character B.",
            expected: "Live character, profile match, and map state refresh. No stale identity."),
        QACheckDefinition(
            id: "resilience.longSession", group: .resilience, title: "Long play session",
            requiredAction: "Play a real session for 30+ minutes on device, or run Developer soak first.",
            expected: "No crash, no duplicate sockets, map remains usable. Soak does not replace device testing."),

        QACheckDefinition(
            id: "session.createGoal", group: .session, title: "Create goal",
            requiredAction: "Create or select a goal on the physical device.",
            expected: "The goal persists locally."),
        QACheckDefinition(
            id: "session.plan", group: .session, title: "Plan session",
            requiredAction: "Build a session plan from Today/goals.",
            expected: "The plan is explainable and local."),
        QACheckDefinition(
            id: "session.start", group: .session, title: "Start session",
            requiredAction: "Start the planned session.",
            expected: "The session survives backgrounding."),
        QACheckDefinition(
            id: "session.navigate", group: .session, title: "Navigate",
            requiredAction: "Navigate to a live target during the session.",
            expected: "The map target matches the session task."),
        QACheckDefinition(
            id: "session.refreshProgress", group: .session, title: "Refresh progress",
            requiredAction: "Refresh account/Today progress during the session.",
            expected: "Progress updates without resetting locked/skipped tasks.")
    ]

    static func definition(id: String) -> QACheckDefinition? {
        checks.first { $0.id == id }
    }

    static func checks(in group: QACheckGroup) -> [QACheckDefinition] {
        checks.filter { $0.group == group }
    }
}

enum AccountDataSource: String, Codable, Sendable {
    case live
    case cached
    case unknown

    var qaLabel: String {
        switch self {
        case .live: "LIVE ACCOUNT RESPONSE"
        case .cached: "CACHED"
        case .unknown: "UNKNOWN"
        }
    }
}

enum TileCoverageReason: String, Codable, Sendable {
    case withinKnownPaintedCoverage
    case outsideKnownPaintedCoverage
    case tileUnavailable
    case mapMetadataMissing

    var title: String {
        switch self {
        case .withinKnownPaintedCoverage: "within known painted coverage"
        case .outsideKnownPaintedCoverage: "outside known painted coverage"
        case .tileUnavailable: "tile unavailable"
        case .mapMetadataMissing: "map metadata not loaded"
        }
    }
}

struct APIDomainStatus: Codable, Equatable, Sendable, Identifiable {
    var id: String { domain }
    var domain: String
    var httpStatus: Int?
    var message: String
    var usedCache: Bool
    var updatedAt: Date

    var summary: String {
        let code = httpStatus.map(String.init) ?? "—"
        return "\(domain): \(code) \(message)"
    }
}

struct ConnectionTransition: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var at: Date
    var from: String
    var to: String

    init(id: UUID = UUID(), at: Date = Date(), from: String, to: String) {
        self.id = id
        self.at = at
        self.from = from
        self.to = to
    }
}

struct DeveloperEvent: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var at: Date
    var message: String

    init(id: UUID = UUID(), at: Date = Date(), message: String) {
        self.id = id
        self.at = at
        self.message = message
    }

    func line(formatter: DateFormatter) -> String {
        "\(formatter.string(from: at)) \(message)"
    }
}

enum QADomain: String, CaseIterable, Sendable {
    case account, characters, inventory, builds, achievements, today

    var title: String {
        switch self {
        case .account: "Account"
        case .characters: "Characters"
        case .inventory: "Inventory"
        case .builds: "Builds"
        case .achievements: "Achievements"
        case .today: "Today"
        }
    }
}

struct QADomainRefreshResult: Equatable, Sendable, Identifiable {
    var id: QADomain { domain }
    var domain: QADomain
    var success: Bool
    var httpStatus: Int?
    var message: String
    var usedCache: Bool
    var timestamp: Date
}
