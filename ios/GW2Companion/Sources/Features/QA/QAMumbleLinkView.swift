import SwiftUI

struct QAMumbleLinkView: View {
    @EnvironmentObject private var telemetry: TelemetryStore
    @AppStorage(QAResultStore.revealIdentityKey) private var revealIdentity = false

    var body: some View {
        List {
            Toggle("Reveal character name", isOn: $revealIdentity)
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                Section("MumbleLink") {
                    labeled("Status", telemetry.state.label)
                    labeled("uiVersion", telemetry.latest?.uiVersion.map(String.init) ?? "not in envelope")
                    labeled("uiTick", telemetry.latest?.uiTick.formatted() ?? "—")
                    labeled("Character", QARedaction.name(telemetry.latest?.character?.name, reveal: revealIdentity))
                    labeled("Map ID", telemetry.latest?.map?.id.formatted() ?? "—")
                    labeled("Profession", professionLabel)
                    labeled("playerX", fmt(telemetry.latest?.player?.continentX))
                    labeled("playerY", fmt(telemetry.latest?.player?.continentY))
                    labeled("Avatar XYZ", avatarXYZ)
                    labeled("Avatar Front", avatarFront)
                    labeled("Camera Front", cameraFront)
                    labeled("Mount", telemetry.latest?.mount.index.formatted() ?? "—")
                    labeled("Combat", telemetry.latest?.ui.inCombat == true ? "yes" : "no")
                    labeled("Telemetry age", telemetry.telemetryAge.map { String(format: "%.1fs", $0) } ?? "—")
                    labeled("Packets/sec", "\(telemetry.packetsPerSecond)")
                }
            }
        }
        .navigationTitle("MumbleLink")
        .font(.caption.monospaced())
        .accessibilityIdentifier("qa.mumble")
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
    }

    private func fmt(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(3)))
    }

    private var professionLabel: String {
        guard let id = telemetry.latest?.character?.profession else { return "—" }
        let names = [1: "Guardian", 2: "Warrior", 3: "Engineer", 4: "Ranger", 5: "Thief",
                     6: "Elementalist", 7: "Mesmer", 8: "Necromancer", 9: "Revenant"]
        return names[id].map { "\($0) (\(id))" } ?? "\(id)"
    }

    private var avatarXYZ: String {
        guard let player = telemetry.latest?.player else { return "—" }
        return "\(fmt(player.avatarX)), \(fmt(player.avatarY)), \(fmt(player.avatarZ))"
    }

    private var avatarFront: String {
        guard let player = telemetry.latest?.player else { return "—" }
        return "\(fmt(player.headingX)), \(fmt(player.headingY))"
    }

    private var cameraFront: String {
        guard let camera = telemetry.latest?.camera else { return "—" }
        return "\(fmt(camera.frontX)), \(fmt(camera.frontY)), \(fmt(camera.frontZ))"
    }
}
