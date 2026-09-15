import Foundation
import UIKit

enum QAExportFactory {
    @MainActor
    static func context(
        telemetry: TelemetryStore,
        account: AccountStore,
        today: TodayStore,
        goals: GoalStore,
        objectives: MapObjectiveStore,
        qa: QAResultStore,
        diagnostics: DeveloperDiagnostics,
        secrets: QARedactionSecrets
    ) -> QAExportContext {
        QAExportContext(
            appVersion: AppBuildInfo.version,
            build: AppBuildInfo.build,
            iosVersion: AppDeviceInfo.systemVersion,
            deviceModel: AppDeviceInfo.modelIdentifier,
            bridgeVersion: telemetry.bridgeVersion,
            telemetryProtocolVersion: telemetry.latest?.protocolVersion ?? BridgeProtocol.current,
            connectionState: telemetry.state.qaKey,
            connectionTransitions: diagnostics.transitions,
            qaResults: QACatalog.checks.map { qa.result(for: $0.id) },
            map: diagnostics.mapSnapshot,
            telemetryPacketsPerSecond: telemetry.packetsPerSecond,
            telemetryAgeSeconds: telemetry.telemetryAge,
            apiPermissions: account.tokenInfo?.permissions.sorted() ?? [],
            accountSource: account.dataSource,
            accountMetadataUpdatedAt: account.accountMetadataUpdatedAt,
            charactersUpdatedAt: account.charactersUpdatedAt,
            inventoryUpdatedAt: account.inventoryUpdatedAt,
            todayUpdatedAt: today.lastUpdatedAt,
            todaySource: today.dataSource,
            pricesUpdatedAt: goals.pricesUpdatedAt,
            apiDomains: Array(diagnostics.apiDomains.values),
            events: diagnostics.events,
            memory: MemoryDiagnostics.snapshot(
                telemetryPacketsPerSecond: telemetry.packetsPerSecond,
                activeMapMarkers: objectives.visibleObjectives.count,
                activeObjectives: objectives.objectives.count),
            secrets: secrets)
    }

    @MainActor
    static func secrets(account: AccountStore, telemetry: TelemetryStore) -> QARedactionSecrets {
        QARedactionSecrets(
            apiKey: try? CredentialStore().getAPIKey(),
            pairingToken: telemetry.savedPairing?.token,
            accountName: account.account?.name,
            characterNames: account.characters.map(\.name) + [telemetry.latest?.character?.name].compactMap { $0 },
            portraitURLs: [])
    }
}
