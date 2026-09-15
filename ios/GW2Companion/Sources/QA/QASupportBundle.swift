import Foundation

struct QAExportContext: Equatable, Sendable {
    var appVersion: String
    var build: String
    var iosVersion: String
    var deviceModel: String
    var bridgeVersion: String?
    var telemetryProtocolVersion: Int
    var connectionState: String
    var connectionTransitions: [ConnectionTransition]
    var qaResults: [QACheckResult]
    var map: MapQADiagnosticsSnapshot
    var telemetryPacketsPerSecond: Int
    var telemetryAgeSeconds: Double?
    var apiPermissions: [String]
    var accountSource: AccountDataSource
    var accountMetadataUpdatedAt: Date?
    var charactersUpdatedAt: Date?
    var inventoryUpdatedAt: Date?
    var todayUpdatedAt: Date?
    var todaySource: AccountDataSource
    var pricesUpdatedAt: Date?
    var apiDomains: [APIDomainStatus]
    var events: [DeveloperEvent]
    var memory: MemoryDiagnosticsSnapshot?
    var secrets: QARedactionSecrets
}

struct QAExportDocument: Codable, Equatable, Sendable {
    static let schemaVersion = QACatalog.reportSchemaVersion

    var schemaVersion: Int
    var generatedAt: String
    var appVersion: String
    var build: String
    var iosVersion: String
    var deviceModel: String
    var bridgeVersion: String?
    var telemetryProtocolVersion: Int
    var connectionState: String
    var connectionTransitions: [QAExportTransition]
    var qaResults: [QAExportCheck]
    var map: MapQADiagnosticsSnapshot
    var telemetryPacketsPerSecond: Int
    var telemetryAgeSeconds: Double?
    var apiPermissions: [String]
    var accountSource: String
    var accountMetadataUpdatedAt: String?
    var charactersUpdatedAt: String?
    var inventoryUpdatedAt: String?
    var todayUpdatedAt: String?
    var todaySource: String
    var pricesUpdatedAt: String?
    var apiDomains: [QAExportAPIDomain]
    var events: [QAExportEvent]
    var memory: MemoryDiagnosticsSnapshot?
    var failureNotes: [String]
    var redaction: String
}

struct QAExportTransition: Codable, Equatable, Sendable {
    var at: String
    var from: String
    var to: String
}

struct QAExportCheck: Codable, Equatable, Sendable {
    var id: String
    var state: String
    var note: String?
    var testedAt: String?
    var severity: String?
}

struct QAExportAPIDomain: Codable, Equatable, Sendable {
    var domain: String
    var httpStatus: Int?
    var message: String
    var usedCache: Bool
    var updatedAt: String
}

struct QAExportEvent: Codable, Equatable, Sendable {
    var at: String
    var message: String
}

enum QASupportBundle {
    static func make(context: QAExportContext, now: Date = Date()) -> QAExportDocument {
        let secrets = context.secrets
        let results = context.qaResults.sorted { $0.id < $1.id }
        let failureNotes = results.compactMap { result -> String? in
            guard result.state == .failed else { return nil }
            let note = result.note.map { QARedaction.scrub($0, secrets: secrets) } ?? ""
            let severity = result.severity?.title ?? "unspecified"
            return "\(result.id) [\(severity)] \(note)".trimmingCharacters(in: .whitespaces)
        }
        return QAExportDocument(
            schemaVersion: QAExportDocument.schemaVersion,
            generatedAt: now.ISO8601Format(),
            appVersion: context.appVersion,
            build: context.build,
            iosVersion: context.iosVersion,
            deviceModel: context.deviceModel,
            bridgeVersion: context.bridgeVersion,
            telemetryProtocolVersion: context.telemetryProtocolVersion,
            connectionState: context.connectionState,
            connectionTransitions: context.connectionTransitions.suffix(20).map {
                QAExportTransition(at: $0.at.ISO8601Format(), from: $0.from, to: $0.to)
            },
            qaResults: results.map {
                QAExportCheck(
                    id: $0.id,
                    state: $0.state.rawValue,
                    note: $0.note.map { QARedaction.scrub($0, secrets: secrets) },
                    testedAt: $0.testedAt?.ISO8601Format(),
                    severity: $0.severity?.rawValue)
            },
            map: context.map.redacted(),
            telemetryPacketsPerSecond: context.telemetryPacketsPerSecond,
            telemetryAgeSeconds: context.telemetryAgeSeconds,
            apiPermissions: context.apiPermissions,
            accountSource: context.accountSource.qaLabel,
            accountMetadataUpdatedAt: context.accountMetadataUpdatedAt?.ISO8601Format(),
            charactersUpdatedAt: context.charactersUpdatedAt?.ISO8601Format(),
            inventoryUpdatedAt: context.inventoryUpdatedAt?.ISO8601Format(),
            todayUpdatedAt: context.todayUpdatedAt?.ISO8601Format(),
            todaySource: context.todaySource.qaLabel,
            pricesUpdatedAt: context.pricesUpdatedAt?.ISO8601Format(),
            apiDomains: context.apiDomains.sorted { $0.domain < $1.domain }.map {
                QAExportAPIDomain(
                    domain: $0.domain,
                    httpStatus: $0.httpStatus,
                    message: QARedaction.scrub($0.message, secrets: secrets),
                    usedCache: $0.usedCache,
                    updatedAt: $0.updatedAt.ISO8601Format())
            },
            events: context.events.suffix(QALogLimits.eventLimit).map {
                QAExportEvent(
                    at: $0.at.ISO8601Format(),
                    message: QARedaction.scrub($0.message, secrets: secrets))
            },
            memory: context.memory,
            failureNotes: failureNotes,
            redaction: "account name, character names, API key, pairing token, portraits, and inventory contents omitted")
    }

    static func jsonString(_ document: QAExportDocument) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(document) else { return "Support bundle could not be generated." }
        return String(decoding: data, as: UTF8.self)
    }

    static func readableText(_ document: QAExportDocument) -> String {
        var lines: [String] = [
            "GW2 Companion support bundle",
            "schema \(document.schemaVersion)",
            "generated \(document.generatedAt)",
            "app \(document.appVersion) (\(document.build))",
            "iOS \(document.iosVersion) \(document.deviceModel)",
            "bridge \(document.bridgeVersion ?? "unknown") protocol \(document.telemetryProtocolVersion)",
            "connection \(document.connectionState)",
            "telemetry \(document.telemetryPacketsPerSecond) packets/sec age \(document.telemetryAgeSeconds.map { String(format: "%.1fs", $0) } ?? "n/a")",
            "permissions \(document.apiPermissions.joined(separator: ", "))",
            "account \(document.accountSource) metadata \(document.accountMetadataUpdatedAt ?? "never") characters \(document.charactersUpdatedAt ?? "never") inventory \(document.inventoryUpdatedAt ?? "never")",
            "today \(document.todaySource) \(document.todayUpdatedAt ?? "never")",
            "prices \(document.pricesUpdatedAt ?? "never")",
            "map id \(document.map.mapID.map(String.init) ?? "—") \(document.map.mapName ?? "") continent \(document.map.continentID.map(String.init) ?? "—") floor \(document.map.floor.map(String.init) ?? "—")",
            "artwork \(document.map.artworkAvailable ? "available" : "unavailable") (\(document.map.coverageReason.title))",
            "",
            "QA RESULTS"
        ]
        for check in document.qaResults {
            lines.append("- \(check.id): \(check.state)\(check.severity.map { " [\($0)]" } ?? "")\(check.note.map { " — \($0)" } ?? "")")
        }
        lines.append("")
        lines.append("API DOMAINS")
        for domain in document.apiDomains {
            lines.append("- \(domain.domain) \(domain.httpStatus.map(String.init) ?? "—") \(domain.message)\(domain.usedCache ? " CACHED" : "")")
        }
        lines.append("")
        lines.append("CONNECTION TRANSITIONS")
        for transition in document.connectionTransitions {
            lines.append("- \(transition.at) \(transition.from) → \(transition.to)")
        }
        lines.append("")
        lines.append("EVENT LOG")
        for event in document.events {
            lines.append("- \(event.at) \(event.message)")
        }
        lines.append("")
        lines.append(document.redaction)
        return lines.joined(separator: "\n")
    }
}

enum AppDeviceInfo {
    static var modelIdentifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    static var systemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
