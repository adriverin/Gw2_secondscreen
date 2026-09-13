import SwiftUI
import UIKit

struct NavigatorPanelView: View {
    enum Section: String, CaseIterable, Identifiable { case nearby = "Nearby", route = "Route"; var id: Self { self } }

    let player: ContinentPoint?
    let onSelect: (MapObjective) -> Void
    @EnvironmentObject private var store: MapObjectiveStore
    @State private var section: Section = .nearby
    @State private var search = ""

    var body: some View {
        VStack(spacing: 12) {
            Picker("Navigator", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if section == .nearby { nearbyContent }
            else { routeContent }
        }
        .navigationTitle("Navigator")
    }

    private var nearbyContent: some View {
        VStack(spacing: 8) {
            TextField("Search this map", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            Picker("Nearby filter", selection: $store.nearbyFilter) {
                ForEach(NearbyFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            List(search.isEmpty ? store.nearby.map(\.objective) : store.search(search)) { objective in
                Button { onSelect(objective) } label: {
                    ObjectiveRow(objective: objective, player: player)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .overlay {
                if store.objectives.isEmpty && store.state == .loading {
                    ProgressView("Loading objectives…")
                }
            }
        }
    }

    private var routeContent: some View {
        VStack(spacing: 8) {
            if let route = store.route, !route.objectives.isEmpty {
                List {
                    ForEach(Array(route.objectives.enumerated()), id: \.element) { index, id in
                        if let objective = store.objective(id) {
                            Button { onSelect(objective) } label: {
                                HStack {
                                    Image(systemName: routeSymbol(index: index, objective: objective))
                                        .foregroundStyle(index == route.currentIndex ? .cyan : .secondary)
                                    ObjectiveRow(objective: objective, player: player)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            Label("Objective on another map", systemImage: "map")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: store.removeRouteObjectives)
                    .onMove(perform: store.moveRouteObjectives)
                }
                .listStyle(.plain)

                if route.currentObjectiveID.flatMap(store.objective) == nil {
                    Text("Next objective is on another map. Navigate there in Guild Wars 2.")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                }

                if let finished = route.finishedAt, let started = route.startedAt {
                    let visited = route.objectives.compactMap(store.objective).filter { $0.state == .visited }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("ROUTE COMPLETE").font(.caption.bold()).foregroundStyle(.green)
                        LabeledContent("Observed visits", value: String(visited.count))
                        LabeledContent("Duration", value: "\(max(1, Int(finished.timeIntervalSince(started) / 60))) min")
                    }
                    .font(.caption)
                    .padding(.horizontal)
                }

                HStack {
                    Button { store.previousRouteObjective() } label: { Image(systemName: "backward.fill") }
                    Button(route.startedAt == nil ? "Start route" : "Next") {
                        route.startedAt == nil ? store.startRoute() : store.advanceRoute()
                    }
                    .buttonStyle(.borderedProminent)
                    if let id = route.currentObjectiveID {
                        Button("Skip") { store.skip(id) }.buttonStyle(.bordered)
                    }
                    Button("Stop") { store.stopRoute() }.buttonStyle(.bordered)
                    EditButton()
                }
                .padding(.horizontal)
            } else {
                ContentUnavailableView(
                    "No route yet", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    description: Text("Add objectives from their details or create a suggested geometric order."))
                if let player {
                    Button("Generate from visible objectives") { store.generateRoute(from: player) }
                        .buttonStyle(.borderedProminent)
                }
            }
            Text("Suggested order uses coordinate distance only; terrain, portals and vertical levels are not considered.")
                .font(.caption2).foregroundStyle(.secondary).padding([.horizontal, .bottom])
        }
    }

    private func routeSymbol(index: Int, objective: MapObjective) -> String {
        if objective.state == .visited || objective.state == .manuallyCompleted { return "checkmark.circle.fill" }
        if store.route?.currentIndex == index { return "arrow.right.circle.fill" }
        return "circle"
    }
}

struct ObjectiveRow: View {
    let objective: MapObjective
    let player: ContinentPoint?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: objective.type.symbol).frame(width: 24).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(objective.name).font(.subheadline.bold()).lineLimit(2)
                Text(objective.type.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let player {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ObjectiveDistanceEngine.cardinalDirection(from: player, to: objective.coordinate).rawValue).bold()
                    Text(ObjectiveDistanceEngine.distance(from: player, to: objective.coordinate), format: .number.precision(.fractionLength(0)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var color: Color {
        switch objective.state {
        case .visited: .yellow
        case .manuallyCompleted: .green
        case .skipped: .secondary
        case .unknown: .orange
        }
    }
}

struct ObjectiveDetailView: View {
    let objectiveID: MapObjectiveID
    let player: ContinentPoint?
    let heading: Double
    @EnvironmentObject private var store: MapObjectiveStore
    @EnvironmentObject private var gathering: GatheringStore
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Group {
                if let objective = store.objective(objectiveID) {
                    Form {
                    Section {
                        Label(objective.name, systemImage: objective.type.symbol).font(.headline)
                        LabeledContent("Type", value: objective.type.title)
                        LabeledContent("Status", value: store.sessionVisitedIDs.contains(objective.id) ? "Visited this session" : objective.state.label)
                        if let level = objective.level { LabeledContent("Level", value: String(level)) }
                        if let description = objective.description, !description.isEmpty { Text(description) }
                    }
                    if let player {
                        let bearing = ObjectiveDistanceEngine.bearing(from: player, to: objective.coordinate)
                        Section("Navigation") {
                            LabeledContent("Direction", value: ObjectiveDistanceEngine.cardinalDirection(from: player, to: objective.coordinate).rawValue)
                            LabeledContent("Distance", value: "\(ObjectiveDistanceEngine.distance(from: player, to: objective.coordinate).formatted(.number.precision(.fractionLength(0)))) coordinate units")
                            LabeledContent("Bearing", value: "\(bearing.formatted(.number.precision(.fractionLength(0))))°")
                            let relative = ObjectiveDistanceEngine.relativeAngle(targetBearing: bearing, playerHeadingRadians: heading)
                            Text(relativeDescription(relative)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        Button("Set as Target") { store.setTarget(objective); dismiss() }
                        Button("Add to Route") { store.addToRoute(objective) }
                        if objective.state == .manuallyCompleted {
                            Button("Remove manual completion") { store.restoreUnknown(objective.id) }
                        } else {
                            Button("Mark Complete") { store.markManuallyCompleted(objective.id) }
                        }
                        Button("Skip", role: .destructive) { store.skip(objective.id) }
                        if objective.type.isGathering {
                            Button("Toggle harvested") {
                                gathering.toggleHarvested(objective.id.rawValue.replacingOccurrences(of: "gathering:", with: ""))
                            }
                        }
                    }
                    if let chatLink = objective.chatLink, !chatLink.isEmpty {
                        Section("In-game chat link") {
                            Text(chatLink).textSelection(.enabled).monospaced()
                            Button(copied ? "Copied" : "Copy Chat Link") {
                                UIPasteboard.general.string = chatLink
                                copied = true
                            }
                        }
                    }
                    Section {
                        Text("Visited and Marked complete are local Companion states. They do not claim Guild Wars 2 character completion.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    }
                    .navigationTitle(objective.type.title.uppercased())
                } else {
                    ContentUnavailableView("Objective unavailable", systemImage: "map")
                }
            }
            .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }

    private func relativeDescription(_ angle: Double) -> String {
        if abs(angle) < 8 { return "Target is straight ahead" }
        return "Target is \(abs(angle).formatted(.number.precision(.fractionLength(0))))° to your \(angle < 0 ? "left" : "right")"
    }
}
