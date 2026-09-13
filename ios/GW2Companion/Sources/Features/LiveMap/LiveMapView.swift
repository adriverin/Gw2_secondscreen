import SwiftUI

struct LiveMapView: View {
    let api: GW2APIClient
    @EnvironmentObject private var telemetry: TelemetryStore
    @EnvironmentObject private var gathering: GatheringStore
    @EnvironmentObject private var objectives: MapObjectiveStore
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var goals: GoalStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var metadata: GW2MapMetadata?
    @State private var metadataFailed = false
    @State private var followPlayer = true
    @State private var showingLayers = false
    @State private var showingPairing = false
    @State private var showingNavigator = false
    @State private var selectedObjectiveID: MapObjectiveID?
    @State private var characterPanelExpanded = false
    @State private var focusRequest: MapFocusRequest?
    @State private var goalAction: SuggestedAction?

    private var playerPoint: ContinentPoint? {
        guard telemetry.latest?.positionAvailable == true, let player = telemetry.latest?.player else { return nil }
        return ContinentPoint(x: player.continentX, y: player.continentY)
    }

    private var heading: Double {
        guard let player = telemetry.latest?.player else { return 0 }
        return atan2(player.headingX, -player.headingY)
    }

    var body: some View {
        NavigationStack {
            Group {
                if horizontalSizeClass == .regular {
                    HStack(spacing: 0) {
                        mapSurface
                        Divider()
                        VStack(spacing: 0) {
                            if let goal = goals.activeGoals.first {
                                mapGoalPanel(goal)
                                Divider()
                            }
                            NavigatorPanelView(player: playerPoint, onSelect: select)
                        }
                        .frame(minWidth: 280, idealWidth: 310, maxWidth: 340)
                        .background(.regularMaterial)
                    }
                } else {
                    mapSurface
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingLayers) { LayerPanelView() }
            .sheet(isPresented: $showingPairing) { PairingView() }
            .sheet(isPresented: $showingNavigator) {
                NavigationStack { NavigatorPanelView(player: playerPoint, onSelect: select) }
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $selectedObjectiveID) { id in
                ObjectiveDetailView(objectiveID: id, player: playerPoint, heading: heading)
            }
            .task(id: telemetry.latest?.map?.id) {
                guard let mapId = telemetry.latest?.map?.id else {
                    metadata = nil
                    gathering.clear()
                    objectives.clear()
                    return
                }
                objectives.transition(to: mapId)
                await loadMap(mapId)
            }
            .onChange(of: playerPoint) { _, point in
                guard let point else { return }
                gathering.updatePlayer(point)
                objectives.updatePlayer(point)
            }
            .onChange(of: telemetry.latest?.character?.name, initial: true) { _, name in
                account.updateLiveCharacter(name: name)
                objectives.setIdentity(accountID: account.account?.id, characterName: name)
            }
            .onChange(of: account.account?.id, initial: true) { _, id in
                objectives.setIdentity(accountID: id, characterName: telemetry.latest?.character?.name)
            }
            .onChange(of: objectives.currentTargetID) { _, id in
                if id != nil { focusRequest = MapFocusRequest(mode: .both) }
            }
            .task(id: objectives.arrivalNotice?.id) {
                guard objectives.arrivalNotice != nil else { return }
                try? await Task.sleep(for: .seconds(4))
                objectives.clearArrivalNotice()
            }
            .task(id: goalContextID) { refreshGoalAction() }
        }
    }

    private var mapSurface: some View {
        ZStack {
            NativeTileMapView(
                player: playerPoint, heading: heading, metadata: metadata,
                objectives: objectives.visibleObjectives, sceneVersion: objectives.sceneRevision,
                harvested: gathering.harvested, target: objectives.currentTarget,
                followPlayer: $followPlayer, focusRequest: focusRequest,
                onSelectObjective: select)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 10) {
                header
                connectionBanner
                if let notice = objectives.arrivalNotice { arrivalBanner(notice) }
                if metadataFailed { unavailableArtworkBanner }
                objectiveStatusBanner
                Spacer()
                if horizontalSizeClass != .regular, let goal = goals.activeGoals.first { mapGoalPanel(goal) }
                if let target = objectives.currentTarget { targetCard(target) }
                currentCharacterPanel
                controls
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private func mapGoalPanel(_ goal: PlayerGoal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACTIVE GOAL").font(.caption2.bold()).foregroundStyle(.secondary)
                    Text(goal.title).font(.subheadline.bold()).lineLimit(1)
                }
                Spacer()
                Button("Open") { goals.selectedGoalID = goal.id; navigation.selectedTab = .goals }
                    .font(.caption.bold())
            }
            if let action = goalAction {
                Text("Next useful: \(action.title)").font(.caption).lineLimit(2)
                if [.navigate, .gather].contains(action.type), !action.objectiveIDs.isEmpty {
                    Button("Show") { navigate(action, goal: goal) }
                        .buttonStyle(.borderedProminent).tint(GWPalette.accent)
                }
            }
        }
        .padding(12)
        .background(horizontalSizeClass == .regular ? AnyShapeStyle(.clear) : AnyShapeStyle(.regularMaterial),
                    in: RoundedRectangle(cornerRadius: 15))
    }

    private var goalContextID: String {
        "\(goals.activeGoals.first?.id.uuidString ?? "none")-\(account.accountLastRefreshedAt?.timeIntervalSince1970 ?? 0)-\(objectives.sceneRevision)-\(telemetry.latest?.map?.id ?? -1)-\(goals.recipeIndex?.builtAt.timeIntervalSince1970 ?? 0)"
    }

    private func refreshGoalAction() {
        guard let goal = goals.activeGoals.first else { goalAction = nil; return }
        var names = goals.craftableItems.mapValues(\.name)
        account.itemMetadata.forEach { names[$0.key] = $0.value.name }
        let actions = SuggestedActionEngine.actions(
            for: goal, craftingPlan: goals.craftingPlan(for: goal, account: account),
            achievement: goals.achievementTracking(for: goal, account: account),
            context: SuggestedActionContext(
                currentMapID: telemetry.latest?.map?.id, playerPosition: playerPoint,
                mapObjectives: objectives.objectives, prices: goals.marketPrices, itemNames: names,
                craftableItemIDs: Set(goals.recipeIndex?.recipeIDsByOutputItem.keys.map { $0 } ?? [])))
        goalAction = actions.first
    }

    private func navigate(_ action: SuggestedAction, goal: PlayerGoal) {
        let all = objectives.objectives + goal.mapLinks.map(\.objective)
        let values = action.objectiveIDs.compactMap { id in all.first { $0.id == id } }
        if action.type == .gather { objectives.applyPreset(.gather) }
        objectives.startGoalRoute(name: goal.title, objectives: values)
        focusRequest = MapFocusRequest(mode: .both)
    }

    private func select(_ objective: MapObjective) {
        focusRequest = MapFocusRequest(mode: .coordinate(objective.coordinate))
        selectedObjectiveID = objective.id
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(metadata?.name ?? telemetry.latest?.map.map { "Map ID \($0.id)" } ?? "Live Map").font(.headline)
                Text("\(objectives.visibleObjectives.count) visible objectives")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { if telemetry.state == .unpaired { showingPairing = true } } label: {
                Text(telemetry.state.label).font(.caption2.bold()).foregroundStyle(statusColor)
                    .padding(.horizontal, 9).padding(.vertical, 6).background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15)).padding(.top, 8)
    }

    private func targetCard(_ target: MapObjective) -> some View {
        Button { select(target) } label: {
            HStack(spacing: 10) {
                Image(systemName: "scope").font(.title3).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT • \(target.type.title.uppercased())").font(.caption2).foregroundStyle(.secondary)
                    Text(target.name).font(.subheadline.bold()).lineLimit(1)
                }
                Spacer()
                if let playerPoint {
                    VStack(alignment: .trailing) {
                        Text(ObjectiveDistanceEngine.cardinalDirection(from: playerPoint, to: target.coordinate).rawValue).bold()
                        Text("\(ObjectiveDistanceEngine.distance(from: playerPoint, to: target.coordinate).formatted(.number.precision(.fractionLength(0)))) units")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(11).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button { showingLayers = true } label: { Label("Layers", systemImage: "square.3.layers.3d") }
                .buttonStyle(MapControlButtonStyle())
            if horizontalSizeClass != .regular {
                Button { showingNavigator = true } label: { Label("Nearby", systemImage: "list.bullet") }
                    .buttonStyle(MapControlButtonStyle())
            }
            Spacer()
            Button { focusRequest = MapFocusRequest(mode: .player) } label: { Image(systemName: "location.fill") }
                .buttonStyle(MapControlButtonStyle()).accessibilityLabel("Center player")
            if objectives.currentTarget != nil {
                Button { focusRequest = MapFocusRequest(mode: .target) } label: { Image(systemName: "scope") }
                    .buttonStyle(MapControlButtonStyle()).accessibilityLabel("Center target")
                Button { focusRequest = MapFocusRequest(mode: .both) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(MapControlButtonStyle()).accessibilityLabel("Fit player and target")
            }
            Button { showingPairing = true } label: { Image(systemName: "desktopcomputer") }
                .buttonStyle(MapControlButtonStyle())
        }
    }

    @ViewBuilder
    private var objectiveStatusBanner: some View {
        switch objectives.state {
        case .loading: statusBanner("Loading official map objectives…", symbol: "map")
        case .loaded where objectives.objectives.isEmpty:
            statusBanner("No official objectives were returned for this map and floor.", symbol: "map")
        case let .unavailable(message):
            statusBanner("Objectives unavailable: \(message)", symbol: "exclamationmark.triangle")
        default:
            switch gathering.availability {
            case .unavailable: statusBanner("Known gathering locations are not available for this map.", symbol: "leaf")
            case .failed: statusBanner("Gathering locations could not be loaded.", symbol: "exclamationmark.triangle")
            default: EmptyView()
            }
        }
    }

    @ViewBuilder
    private var currentCharacterPanel: some View {
        if let liveName = telemetry.latest?.character?.name, !liveName.isEmpty {
            let matched = account.currentCharacter
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    if horizontalSizeClass == .regular { characterPanelExpanded.toggle() }
                    else if let matched { navigation.showCharacter(matched.name) }
                    else { characterPanelExpanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        if let matched {
                            CachedAsyncImage(url: account.professions[matched.profession]?.icon) {
                                Image(systemName: "person.crop.circle.fill")
                            }.frame(width: 34, height: 34)
                        } else {
                            Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(GWPalette.accent)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(liveName).font(.subheadline.bold())
                            if let matched {
                                Text("\(account.eliteSpecializationName(for: matched) ?? matched.profession) • Level \(matched.level)")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(account.connectionState == .disconnected ? "Live character" : "Account character not matched")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        GWBadge(text: "LIVE", color: .green, symbol: "circle.fill")
                    }
                }.buttonStyle(.plain)

                if characterPanelExpanded {
                    if let matched {
                        HStack {
                            characterAction("Equipment", symbol: "shield.fill", character: matched, section: .equipment)
                            characterAction("Build", symbol: "point.3.connected.trianglepath.dotted", character: matched, section: .build)
                            characterAction("Inventory", symbol: "bag.fill", character: matched, section: .inventory)
                        }
                    } else if account.connectionState == .disconnected {
                        Text("Connect your GW2 account for equipment, build and inventory details.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Connect Account") { navigation.selectedTab = .account }
                            .buttonStyle(.borderedProminent).tint(GWPalette.accent)
                    }
                }
            }
            .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
            .frame(maxWidth: horizontalSizeClass == .regular ? 520 : .infinity)
        }
    }

    private func characterAction(_ title: String, symbol: String, character: GW2Character, section: CharacterSection) -> some View {
        Button { navigation.showCharacter(character.name, section: section) } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity)
        }.buttonStyle(.bordered).font(.caption.bold())
    }

    @ViewBuilder
    private var connectionBanner: some View {
        switch telemetry.state {
        case .unpaired:
            VStack(spacing: 8) {
                Label("Connect your gaming PC", systemImage: "desktopcomputer").font(.headline)
                Text("Scan the bridge QR code, enter its LAN address, or start the built-in simulation.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Connect to PC") { showingPairing = true }.buttonStyle(.borderedProminent).tint(.orange)
            }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
        case .gameNotRunning: statusBanner("Guild Wars 2 is not running.", symbol: "gamecontroller")
        case let .positionUnavailable(message): statusBanner(message, symbol: "location.slash")
        case .bridgeOffline: statusBanner("Can't reach your PC. Make sure both devices are on the same network.", symbol: "wifi.slash")
        case .connecting: statusBanner("Connecting to GW2 Companion Bridge…", symbol: "arrow.triangle.2.circlepath")
        case .reconnecting: statusBanner("Connection lost. Reconnecting automatically…", symbol: "arrow.triangle.2.circlepath")
        case .pairAgain:
            VStack(spacing: 8) {
                statusBanner("The bridge pairing changed. Scan its QR code again.", symbol: "qrcode")
                Button("Pair again") { showingPairing = true }.buttonStyle(.borderedProminent).tint(.orange)
            }
        case .live: EmptyView()
        }
    }

    private var unavailableArtworkBanner: some View {
        Label("Map artwork unavailable for this area. Live telemetry remains connected.", systemImage: "map")
            .font(.caption).padding(9).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func statusBanner(_ message: String, symbol: String) -> some View {
        Label(message, systemImage: symbol).font(.caption).padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func arrivalBanner(_ notice: ObjectiveArrivalNotice) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("\(notice.objectiveName) visited", systemImage: "checkmark.circle.fill")
                .font(.subheadline.bold())
            if let next = notice.nextObjectiveName {
                Text("Next: \(next)").font(.caption)
            } else {
                Text("Target reached").font(.caption)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background(.green.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusColor: Color {
        switch telemetry.state {
        case .live: .green
        case .connecting, .reconnecting: .yellow
        default: .orange
        }
    }

    private func loadMap(_ id: Int) async {
        metadataFailed = false
        do {
            let loadedMetadata = try await api.map(id: id)
            guard telemetry.latest?.map?.id == id else { return }
            metadata = loadedMetadata
            async let officialLoad: Void = objectives.load(
                provider: api, metadata: loadedMetadata, language: objectiveLanguage)
            async let gatheringLoad: Void = gathering.load(mapId: id, metadata: loadedMetadata, simulation: telemetry.isSimulating)
            _ = await (officialLoad, gatheringLoad)
            guard telemetry.latest?.map?.id == id else { return }
            objectives.syncGathering(gathering.nodes, mapId: id)
            if let playerPoint { objectives.updatePlayer(playerPoint, force: true) }
        } catch is CancellationError {
            return
        } catch {
            guard telemetry.latest?.map?.id == id else { return }
            metadata = nil
            metadataFailed = true
            gathering.clear()
            objectives.clear()
        }
    }

    private var objectiveLanguage: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return ["en", "de", "es", "fr"].contains(code) ? code : "en"
    }
}

private struct MapControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.bold()).padding(.horizontal, 13).padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule()).opacity(configuration.isPressed ? 0.65 : 1)
    }
}
