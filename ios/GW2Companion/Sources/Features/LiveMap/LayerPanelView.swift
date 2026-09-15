import SwiftUI

struct LayerPanelView: View {
    @EnvironmentObject private var gathering: GatheringStore
    @EnvironmentObject private var objectives: MapObjectiveStore
    @EnvironmentObject private var telemetry: TelemetryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Quick filters") {
                    Picker("Preset", selection: presetBinding) {
                        ForEach(ObjectiveFilterPreset.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                Section("World") {
                    objectiveToggle(.waypoint)
                    objectiveToggle(.vista)
                    objectiveToggle(.landmark)
                    objectiveToggle(.renownHeart)
                    objectiveToggle(.heroChallenge)
                    objectiveToggle(.masteryInsight)
                    objectiveToggle(.adventure)
                }
                Section("Gathering") {
                    if let message = GatheringCoverageCopy.layerMessage(
                        availability: gathering.availability,
                        mapName: objectives.mapMetadata?.name
                    ) {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("layers.gathering.coverage")
                    }
                    LabeledContent("Gathering Data", value: GatheringCoverageCopy.coverageTitle(availability: gathering.availability))
                    objectiveToggle(.gatheringOre)
                    objectiveToggle(.gatheringWood)
                    objectiveToggle(.gatheringPlant)
                    ForEach(GatheringReliability.allCases) { reliability in
                        Toggle("\(reliability.title) locations", isOn: membership(reliability, in: $gathering.reliabilities))
                    }
                    Toggle("Hide marked harvested", isOn: $gathering.hideHarvested)
                }
                Section("Status") {
                    Toggle("Hide visited", isOn: $objectives.hideVisited)
                    Toggle("Hide manually completed", isOn: $objectives.hideManuallyCompleted)
                    Toggle("Auto-advance route", isOn: $objectives.autoAdvance)
                }
                Section {
                    Button("Reset session visits") { objectives.resetSessionVisits() }
                    Button("Reset visits for current map", role: .destructive) { objectives.resetVisitsForCurrentMap() }
                    Button("Reset all companion history", role: .destructive) { objectives.resetAllCompanionHistory() }
                } header: {
                    Text("Companion history")
                } footer: {
                    Text("Visited means this companion observed the player near an objective. Marked complete is a separate manual state and is not Guild Wars 2 API completion.")
                }
#if DEBUG
                Section("Developer diagnostics") {
                    LabeledContent("Map ID", value: objectives.mapMetadata.map { String($0.id) } ?? "—")
                    LabeledContent("Floor", value: objectives.mapMetadata.map { String($0.defaultFloor) } ?? "—")
                    LabeledContent("Region ID", value: objectives.mapMetadata?.regionId.map(String.init) ?? "—")
                    if let player = telemetry.latest?.player {
                        LabeledContent("Player continent", value: "\(player.continentX.formatted(.number.precision(.fractionLength(2)))), \(player.continentY.formatted(.number.precision(.fractionLength(2))))")
                    }
                    if let target = objectives.currentTarget {
                        LabeledContent("Target continent", value: "\(target.continentX.formatted(.number.precision(.fractionLength(2)))), \(target.continentY.formatted(.number.precision(.fractionLength(2))))")
                        LabeledContent("Source", value: target.source.rawValue)
                        LabeledContent("Arrival threshold", value: "\(target.type.arrivalRadius.formatted()) units")
                        if let player = telemetry.latest?.player {
                            let point = ContinentPoint(x: player.continentX, y: player.continentY)
                            LabeledContent("Raw distance", value: ObjectiveDistanceEngine.distance(from: point, to: target.coordinate).formatted(.number.precision(.fractionLength(2))))
                            LabeledContent("Bearing", value: "\(ObjectiveDistanceEngine.bearing(from: point, to: target.coordinate).formatted(.number.precision(.fractionLength(1))))°")
                        }
                    }
                }
#endif
            }
            .navigationTitle("Layers")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private var presetBinding: Binding<ObjectiveFilterPreset> {
        Binding(
            get: { objectives.selectedPreset },
            set: { preset in objectives.applyPreset(preset) })
    }

    private func objectiveToggle(_ type: MapObjectiveType) -> some View {
        Toggle(isOn: membership(type, in: $objectives.visibleTypes)) {
            Label(type.pluralTitle, systemImage: type.symbol)
        }
    }

    private func membership<Element: Hashable>(_ element: Element, in set: Binding<Set<Element>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(element) },
            set: { enabled in
                if enabled { set.wrappedValue.insert(element) }
                else { set.wrappedValue.remove(element) }
            })
    }
}
