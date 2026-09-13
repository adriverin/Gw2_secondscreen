import SwiftUI

struct ObjectiveVisitRecord: Codable, Equatable, Sendable {
    let objectiveID: MapObjectiveID
    let mapId: Int
    let accountID: String?
    let characterName: String?
    let firstVisitedAt: Date
    var lastVisitedAt: Date
    var visitCount: Int
}

private struct ObjectiveManualRecord: Codable, Sendable {
    let objectiveID: MapObjectiveID
    let accountID: String?
    let characterName: String?
    var state: MapObjectiveState
}

private struct ObjectiveHistorySnapshot: Codable, Sendable {
    var visits: [ObjectiveVisitRecord]
    var manual: [ObjectiveManualRecord]
}

enum MapObjectiveLoadState: Equatable {
    case idle
    case loading
    case loaded
    case unavailable(String)
}

enum NearbyFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case world = "World"
    case gathering = "Gathering"
    var id: Self { self }
}

struct ObjectiveArrivalNotice: Identifiable, Equatable {
    let id = UUID()
    let objectiveName: String
    let nextObjectiveName: String?
}

@MainActor
final class MapObjectiveStore: ObservableObject {
    @Published private(set) var objectives: [MapObjective] = []
    @Published private(set) var visibleObjectives: [MapObjective] = []
    @Published private(set) var nearby: [NearbyObjective] = []
    @Published private(set) var currentTargetID: MapObjectiveID?
    @Published private(set) var route: NavigationRoute?
    @Published private(set) var sceneRevision = 0
    @Published private(set) var state: MapObjectiveLoadState = .idle
    @Published private(set) var mapMetadata: GW2MapMetadata?
    @Published private(set) var sessionVisitedIDs: Set<MapObjectiveID> = []
    @Published private(set) var arrivalNotice: ObjectiveArrivalNotice?
    @Published var visibleTypes: Set<MapObjectiveType> { didSet { filtersChanged() } }
    @Published var hideVisited: Bool { didSet { filtersChanged() } }
    @Published var hideManuallyCompleted: Bool { didSet { filtersChanged() } }
    @Published var autoAdvance: Bool { didSet { defaults.set(autoAdvance, forKey: Keys.autoAdvance) } }
    @Published var nearbyFilter: NearbyFilter = .all { didSet { refreshNearby(force: true) } }
    @Published private(set) var selectedPreset: ObjectiveFilterPreset

    private enum Keys {
        static let visibleTypes = "phase3.visibleObjectiveTypes"
        static let hideVisited = "phase3.hideVisited"
        static let hideManual = "phase3.hideManuallyCompleted"
        static let preset = "phase3.objectivePreset"
        static let history = "phase3.objectiveHistory.v1"
        static let route = "phase3.currentRoute.v1"
        static let autoAdvance = "phase3.autoAdvance"
    }

    private let defaults: UserDefaults
    private let proximity: ObjectiveProximityEngine
    private var officialObjectives: [MapObjective] = []
    private var gatheringObjectives: [MapObjective] = []
    private var requestedMapId: Int?
    private var currentMapId: Int?
    private var player: ContinentPoint?
    private var accountID: String?
    private var characterName: String?
    private var history: ObjectiveHistorySnapshot

    init(defaults: UserDefaults = .standard, proximity: ObjectiveProximityEngine = ObjectiveProximityEngine()) {
        self.defaults = defaults
        self.proximity = proximity
        let savedPreset = defaults.string(forKey: Keys.preset).flatMap(ObjectiveFilterPreset.init(rawValue:)) ?? .explore
        selectedPreset = savedPreset
        if defaults.object(forKey: Keys.visibleTypes) != nil {
            visibleTypes = Set((defaults.stringArray(forKey: Keys.visibleTypes) ?? []).compactMap(MapObjectiveType.init(rawValue:)))
        } else {
            visibleTypes = savedPreset.types
        }
        hideVisited = defaults.bool(forKey: Keys.hideVisited)
        hideManuallyCompleted = defaults.bool(forKey: Keys.hideManual)
        autoAdvance = defaults.object(forKey: Keys.autoAdvance) == nil ? true : defaults.bool(forKey: Keys.autoAdvance)
        history = defaults.data(forKey: Keys.history)
            .flatMap { try? JSONDecoder().decode(ObjectiveHistorySnapshot.self, from: $0) }
            ?? ObjectiveHistorySnapshot(visits: [], manual: [])
        route = defaults.data(forKey: Keys.route).flatMap { try? JSONDecoder().decode(NavigationRoute.self, from: $0) }
    }

    var currentTarget: MapObjective? { currentTargetID.flatMap(objective) }
    var currentMapObjectiveCount: Int { objectives.count }

    func setIdentity(accountID: String?, characterName: String?) {
        guard self.accountID != accountID || self.characterName != characterName else { return }
        self.accountID = accountID
        self.characterName = characterName
        applyHistoryAndRefresh()
    }

    func load(
        provider: any MapObjectiveDataProvider,
        metadata: GW2MapMetadata,
        language: String = "en"
    ) async {
        requestedMapId = metadata.id
        currentMapId = metadata.id
        mapMetadata = metadata
        state = .loading
        proximity.reset()
        if currentTarget.map({ $0.mapId != metadata.id }) == true { currentTargetID = nil }
        do {
            let loaded = try await provider.objectives(
                continentId: metadata.continentId, floor: metadata.defaultFloor,
                mapId: metadata.id, language: language)
            guard requestedMapId == metadata.id else { return }
            officialObjectives = loaded.filter { $0.mapId == metadata.id }
            rebuildObjectives()
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard requestedMapId == metadata.id else { return }
            officialObjectives = []
            rebuildObjectives()
            state = .unavailable(error.localizedDescription)
        }
    }

    func syncGathering(_ nodes: [GatheringNode], mapId: Int) {
        guard currentMapId == mapId else { return }
        gatheringObjectives = nodes.filter { $0.mapId == mapId }.map(\.mapObjective)
        rebuildObjectives()
    }

    func transition(to mapId: Int?) {
        guard mapId != currentMapId else { return }
        currentMapId = mapId
        mapMetadata = nil
        requestedMapId = mapId
        officialObjectives = []
        gatheringObjectives = []
        player = nil
        nearby = []
        arrivalNotice = nil
        proximity.reset()
        if currentTarget.map({ $0.mapId != mapId }) == true { currentTargetID = nil }
        rebuildObjectives()
        state = mapId == nil ? .idle : .loading
    }

    func clear() { transition(to: nil) }

    func updatePlayer(_ point: ContinentPoint, now: Date = Date(), force: Bool = false) {
        player = point
        guard let result = proximity.evaluate(
            player: point, objectives: filteredForNearby(), targetID: currentTargetID,
            targetObjective: currentTarget,
            now: now, force: force) else { return }
        nearby = result.nearby
        if !result.newlyVisited.isEmpty {
            let reachedTarget = result.targetReached ? currentTarget : nil
            for id in result.newlyVisited { markVisited(id, at: now) }
            if result.targetReached, autoAdvance { advanceRoute() }
            if let reachedTarget {
                arrivalNotice = ObjectiveArrivalNotice(
                    objectiveName: reachedTarget.name,
                    nextObjectiveName: autoAdvance ? currentTarget?.name : nil)
            }
        }
    }

    func setTarget(_ objective: MapObjective) {
        currentTargetID = objective.id
        refreshNearby(force: true)
    }

    func clearTarget() { currentTargetID = nil }

    func clearArrivalNotice() { arrivalNotice = nil }

    func markManuallyCompleted(_ id: MapObjectiveID) { setManualState(.manuallyCompleted, for: id) }
    func skip(_ id: MapObjectiveID) {
        setManualState(.skipped, for: id)
        if currentTargetID == id { advanceRoute() }
    }

    func restoreUnknown(_ id: MapObjectiveID) { setManualState(.unknown, for: id) }

    func applyPreset(_ preset: ObjectiveFilterPreset) {
        selectedPreset = preset
        defaults.set(preset.rawValue, forKey: Keys.preset)
        visibleTypes = preset.types
    }

    func search(_ query: String) -> [MapObjective] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return visibleObjectives }
        return objectives.filter {
            $0.name.localizedCaseInsensitiveContains(needle) ||
            $0.type.title.localizedCaseInsensitiveContains(needle) ||
            ($0.description?.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }

    func addToRoute(_ objective: MapObjective) {
        if route == nil { route = NavigationRoute(name: "Current Route", objectives: []) }
        guard route?.objectives.contains(objective.id) == false else { return }
        route?.objectives.append(objective.id)
        persistRoute()
    }

    func generateRoute(from start: ContinentPoint, types: Set<MapObjectiveType>? = nil) {
        let candidates = visibleObjectives.filter { objective in
            (types?.contains(objective.type) ?? true) && objective.state != .manuallyCompleted
        }
        route = NavigationRoute(name: "Suggested Order", objectives: RouteGenerator.nearestNeighbor(from: start, objectives: candidates))
        persistRoute()
    }

    func startRoute() {
        guard var route, !route.objectives.isEmpty else { return }
        route.currentIndex = min(route.currentIndex, route.objectives.count - 1)
        route.startedAt = route.startedAt ?? Date()
        route.finishedAt = nil
        self.route = route
        currentTargetID = route.currentObjectiveID
        persistRoute()
    }

    func advanceRoute() {
        guard var route else { currentTargetID = nil; return }
        if route.currentIndex + 1 < route.objectives.count {
            route.currentIndex += 1
            currentTargetID = route.currentObjectiveID
        } else {
            route.finishedAt = Date()
            currentTargetID = nil
        }
        self.route = route
        persistRoute()
    }

    func previousRouteObjective() {
        guard var route, route.currentIndex > 0 else { return }
        route.currentIndex -= 1
        self.route = route
        currentTargetID = route.currentObjectiveID
        persistRoute()
    }

    func stopRoute() {
        currentTargetID = nil
        route?.startedAt = nil
        persistRoute()
    }

    func removeRouteObjectives(at offsets: IndexSet) {
        route?.objectives.remove(atOffsets: offsets)
        if let count = route?.objectives.count, count > 0 {
            route?.currentIndex = min(route?.currentIndex ?? 0, count - 1)
        } else {
            currentTargetID = nil
        }
        persistRoute()
    }

    func moveRouteObjectives(from offsets: IndexSet, to destination: Int) {
        route?.objectives.move(fromOffsets: offsets, toOffset: destination)
        persistRoute()
    }

    func resetSessionVisits() {
        sessionVisitedIDs = []
        applyHistoryAndRefresh()
    }

    func resetVisitsForCurrentMap() {
        guard let currentMapId else { return }
        history.visits.removeAll { $0.mapId == currentMapId && matchesScope($0.accountID, $0.characterName) }
        sessionVisitedIDs.subtract(objectives.map(\.id))
        persistHistory()
        applyHistoryAndRefresh()
    }

    func resetAllCompanionHistory() {
        history = ObjectiveHistorySnapshot(visits: [], manual: [])
        sessionVisitedIDs = []
        persistHistory()
        applyHistoryAndRefresh()
    }

    func objective(_ id: MapObjectiveID) -> MapObjective? { objectives.first { $0.id == id } }

    private func markVisited(_ id: MapObjectiveID, at date: Date) {
        sessionVisitedIDs.insert(id)
        guard let objective = objective(id) else { return }
        if let index = history.visits.firstIndex(where: {
            $0.objectiveID == id && matchesScope($0.accountID, $0.characterName)
        }) {
            history.visits[index].lastVisitedAt = date
            history.visits[index].visitCount += 1
        } else {
            history.visits.append(ObjectiveVisitRecord(
                objectiveID: id, mapId: objective.mapId, accountID: accountID,
                characterName: characterName, firstVisitedAt: date, lastVisitedAt: date, visitCount: 1))
        }
        persistHistory()
        applyHistoryAndRefresh()
    }

    private func setManualState(_ state: MapObjectiveState, for id: MapObjectiveID) {
        history.manual.removeAll {
            $0.objectiveID == id && matchesScope($0.accountID, $0.characterName)
        }
        if state != .unknown {
            history.manual.append(ObjectiveManualRecord(
                objectiveID: id, accountID: accountID, characterName: characterName, state: state))
        }
        persistHistory()
        applyHistoryAndRefresh()
    }

    private func rebuildObjectives() {
        let combined = (officialObjectives + gatheringObjectives).filter { $0.mapId == currentMapId }
        objectives = combined.map { $0.withState(state(for: $0.id)) }
            .sorted { ($0.type.rawValue, $0.name, $0.id.rawValue) < ($1.type.rawValue, $1.name, $1.id.rawValue) }
        refreshVisible()
    }

    private func applyHistoryAndRefresh() {
        objectives = objectives.map { $0.withState(state(for: $0.id)) }
        refreshVisible()
    }

    private func state(for id: MapObjectiveID) -> MapObjectiveState {
        if let manual = history.manual.last(where: {
            $0.objectiveID == id && matchesScope($0.accountID, $0.characterName)
        }) { return manual.state }
        if history.visits.contains(where: {
            $0.objectiveID == id && matchesScope($0.accountID, $0.characterName)
        }) { return .visited }
        return .unknown
    }

    private func matchesScope(_ recordAccount: String?, _ recordCharacter: String?) -> Bool {
        recordAccount == accountID && recordCharacter == characterName
    }

    private func filtersChanged() {
        defaults.set(visibleTypes.map(\.rawValue).sorted(), forKey: Keys.visibleTypes)
        defaults.set(hideVisited, forKey: Keys.hideVisited)
        defaults.set(hideManuallyCompleted, forKey: Keys.hideManual)
        refreshVisible()
    }

    private func refreshVisible() {
        let filtered = objectives.filter {
            visibleTypes.contains($0.type) && (!hideVisited || $0.state != .visited) &&
                (!hideManuallyCompleted || $0.state != .manuallyCompleted)
        }
        if filtered != visibleObjectives {
            visibleObjectives = filtered
            sceneRevision &+= 1
        }
        refreshNearby(force: true)
    }

    private func filteredForNearby() -> [MapObjective] {
        visibleObjectives.filter {
            switch nearbyFilter {
            case .all: true
            case .world: $0.type.isWorld
            case .gathering: $0.type.isGathering
            }
        }
    }

    private func refreshNearby(force: Bool) {
        guard let player, let result = proximity.evaluate(
            player: player, objectives: filteredForNearby(), targetID: currentTargetID,
            targetObjective: currentTarget,
            force: force) else { return }
        nearby = result.nearby
    }

    private func persistHistory() {
        defaults.set(try? JSONEncoder().encode(history), forKey: Keys.history)
    }

    private func persistRoute() {
        if let route {
            defaults.set(try? JSONEncoder().encode(route), forKey: Keys.route)
        } else {
            defaults.removeObject(forKey: Keys.route)
        }
    }
}
