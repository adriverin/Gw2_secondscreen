import SwiftUI

struct LiveMapView: View {
    let api: GW2APIClient
    @EnvironmentObject private var telemetry: TelemetryStore
    @EnvironmentObject private var gathering: GatheringStore
    @EnvironmentObject private var objectives: MapObjectiveStore
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var goals: GoalStore
    @EnvironmentObject private var sessions: SessionStore
    @EnvironmentObject private var today: TodayStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var availableWidth: CGFloat = 0
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
    @State private var viewportCenter = ContinentPoint(x: 0, y: 0)
    @State private var viewportZoom = 6
    @State private var viewportCameraZoom = 6.0
    @State private var viewportTileWorld: TileWorldCoordinate?
    @State private var viewportTile: TileIndex?
    @AppStorage("developer.mode.enabled") private var developerMode = false
    @AppStorage("developer.map.tileGrid") private var showTileDebugGrid = false
    @AppStorage(MapDetailMode.storageKey) private var mapDetailRaw = MapDetailMode.balanced.rawValue
    @AppStorage("map.panel.todayExpanded") private var todayExpanded = false
    @AppStorage("map.panel.goalsExpanded") private var goalsExpanded = false
    @AppStorage("map.panel.sessionExpanded") private var sessionExpanded = false

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
                GeometryReader { geometry in
                if horizontalSizeClass == .regular && geometry.size.width >= 800 {
                    HStack(spacing: 0) {
                        mapSurface
                        if !navigation.navigatorHidden {
                            Divider()
                            VStack(spacing: 0) {
                                if !navigation.mapChromeHidden {
                                    mapSidePanels
                                }
                                NavigatorPanelView(player: playerPoint, onSelect: select)
                            }
                            .frame(width: 280)
                            .background(GWPalette.secondaryBackground)
                        }
                    }
                } else {
                    mapSurface
                }
            }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
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
                showTileDebugGrid: {
#if DEBUG
                    developerMode && showTileDebugGrid
#else
                    false
#endif
                }(),
                showTiles: artworkAvailable,
                onSelectObjective: select,
                onBackgroundTap: { withAnimation(GWPresentation.motion(reduced: reduceMotion)) { navigation.toggleMapChrome() } },
                routeIDs: Set(objectives.route?.objectives ?? []),
                onVisibleCoordinateChange: { center, zoom, tileWorld, tile, tileCount, markerCount, cameraZoom in
                    viewportCenter = center
                    viewportZoom = zoom
                    viewportCameraZoom = cameraZoom
                    viewportTileWorld = tileWorld
                    viewportTile = tile
                    DeveloperDiagnostics.shared.mapSnapshot = MapQADiagnostics.snapshot(
                        metadata: metadata,
                        player: playerPoint,
                        viewport: center,
                        userZoom: zoom,
                        tileWorld: tileWorld,
                        tile: tile,
                        visibleTileCount: tileCount,
                        visibleMarkerCount: markerCount,
                        sourceZoomBias: max(0, MapRasterDetail.sourceZoom(
                            displayZoom: zoom, continentID: metadata?.continentId ?? 1,
                            viewport: MapViewportTransform(
                                center: center, zoom: zoom, magnification: 1, dragOffset: .zero,
                                size: CGSize(width: 390, height: 844),
                                tileReferenceZoom: ArenaNetTileProjection.shared.configuration(
                                    continentID: metadata?.continentId ?? 1).referenceZoom)
                                .visibleContinentRect(marginPoints: 256),
                            mode: MapDetailMode(rawValue: mapDetailRaw) ?? .balanced) - zoom))
                })
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    sidebarRestoreButton
                    compactHUD
                }
                if !navigation.mapChromeHidden { connectionBanner }
                if let notice = objectives.arrivalNotice { arrivalBanner(notice) }
                if metadataFailed || !artworkAvailable { unavailableArtworkBanner }
                if GWPresentation.developerToolsAvailable && developerMode && !navigation.mapChromeHidden { calibrationHUD }
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        if !navigation.mapChromeHidden {
                            if navigation.navigatorHidden || availableWidth < 800 { mapSidePanels.frame(maxWidth: 520) }
                            if let target = objectives.currentTarget { targetCard(target) }
                            currentCharacterPanel
                            controls
                        } else if let target = objectives.currentTarget {
                            immersiveTargetHint(target)
                        }
                    }
                    Spacer()
                    navigatorRestoreButton.padding(.bottom, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var mapSidePanels: some View {
        if sessions.activeSession != nil {
            ActiveSessionCompactView(isExpanded: $sessionExpanded)
                .background(GWPalette.mapOverlay, in: RoundedRectangle(cornerRadius: GWSpacing.large))
        } else if today.snapshot != nil {
            TodayCompactView(isExpanded: $todayExpanded)
                .background(GWPalette.mapOverlay, in: RoundedRectangle(cornerRadius: GWSpacing.large))
        } else if let goal = goals.activeGoals.first {
            mapGoalPanel(goal)
        }
    }

    private var sidebarRestoreButton: some View {
        Button(action: navigation.toggleSidebar) {
            Image(systemName: "sidebar.left")
                .font(.headline)
                .frame(minWidth: 44, minHeight: 44)
                .background(GWPalette.mapOverlay, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(navigation.sidebarHidden ? "Show Navigation" : "Hide Navigation")
        .accessibilityIdentifier("map.chrome.sidebar")
    }

    private var navigatorRestoreButton: some View {
        Button {
            if horizontalSizeClass == .regular && availableWidth >= 800 {
                navigation.toggleNavigator()
            } else if showingNavigator {
                showingNavigator = false
                navigation.navigatorHidden = true
            } else {
                navigation.navigatorHidden = false
                showingNavigator = true
            }
        } label: {
            Image(systemName: "list.bullet.rectangle")
                .font(.headline)
                .frame(minWidth: 44, minHeight: 44)
                .background(GWPalette.mapOverlay, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            (horizontalSizeClass == .regular && availableWidth >= 800 ? navigation.navigatorHidden : !showingNavigator)
                ? "Show Navigator" : "Hide Navigator")
        .accessibilityIdentifier("map.chrome.navigator")
    }

    private var compactHUD: some View {
        HStack(spacing: GWSpacing.medium) {
            if !navigation.mapChromeHidden {
                Text(metadata?.name ?? "Tyria").font(.headline).lineLimit(1)
                Spacer(minLength: GWSpacing.small)
            }
            Button { if telemetry.state != .connectedLive { showingPairing = true } } label: {
                GWBadge(text: telemetry.state == .connectedLive ? "LIVE" : connectionTitle,
                        color: statusColor, symbol: "circle.fill")
            }.buttonStyle(.plain).frame(minHeight: 44)
                .accessibilityLabel(telemetry.state == .connectedLive ? "Live position" : "Connect gaming PC")
        }
        .padding(.horizontal, GWSpacing.medium)
        .background(GWPalette.mapOverlay, in: Capsule())
    }

    private var connectionTitle: String {
        switch telemetry.state {
        case .connectedLive: "LIVE"
        case .connecting, .reconnecting: "CONNECTING"
        case .stale: "WAITING"
        default: "OFFLINE"
        }
    }

    private func immersiveTargetHint(_ target: MapObjective) -> some View {
        HStack {
            Image(systemName: "location.north.fill").foregroundStyle(.cyan)
            Text(target.name).font(.caption.bold()).lineLimit(1)
            Spacer()
        }
        .padding(10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func mapGoalPanel(_ goal: PlayerGoal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { goalsExpanded.toggle() } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GOALS").font(.caption2.bold()).foregroundStyle(.secondary)
                        Text(goal.title).font(.subheadline.bold()).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: goalsExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(goalsExpanded ? "Goals expanded" : "Goals collapsed")
            if goalsExpanded {
                Button("Open") { goals.selectedGoalID = goal.id; navigation.selectedTab = .goals }
                    .font(.caption.bold())
                if let action = goalAction {
                    Text("Next useful: \(action.title)").font(.caption).lineLimit(2)
                    if [.navigate, .gather].contains(action.type), !action.objectiveIDs.isEmpty {
                        Button("Show") { navigate(action, goal: goal) }
                            .buttonStyle(GWPrimaryButtonStyle())
                    }
                }
            }
        }
        .padding(GWSpacing.medium)
        .background(horizontalSizeClass == .regular ? AnyShapeStyle(.clear) : AnyShapeStyle(.regularMaterial),
                    in: RoundedRectangle(cornerRadius: GWSpacing.large))
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
            legendaryPlan: goals.legendaryPlan(for: goal, account: account),
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

    private var header: some View { compactHUD }

    private func targetCard(_ target: MapObjective) -> some View {
        Button { select(target) } label: {
            HStack(spacing: 10) {
                Image(systemName: "scope").font(.title3).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.type.title).font(.caption2).foregroundStyle(.secondary)
                    Text(target.name).font(.subheadline.bold()).lineLimit(1)
                }
                Spacer()
                if let playerPoint {
                    VStack(alignment: .trailing) {
                        Text(ObjectiveDistanceEngine.cardinalDirection(from: playerPoint, to: target.coordinate).rawValue).bold()
                        Text(GWMapDistancePresentation.text(from: playerPoint, to: target.coordinate, metadata: metadata))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(GWSpacing.medium).background(GWPalette.mapOverlay, in: RoundedRectangle(cornerRadius: GWSpacing.large))
        }
        .buttonStyle(.plain)
    }

    private var controls: some View {
        HStack(spacing: GWSpacing.small) {
            Button { showingLayers = true } label: { Label("Layers", systemImage: "square.3.layers.3d") }
                .buttonStyle(MapControlButtonStyle())
            Spacer()
            Menu {
                Toggle("Follow player", isOn: $followPlayer)
                if objectives.currentTarget != nil {
                    Button("Center target") { focusRequest = MapFocusRequest(mode: .target) }
                    Button("Fit player and target") { focusRequest = MapFocusRequest(mode: .both) }
                }
                Button("Gaming PC") { showingPairing = true }
            } label: { Image(systemName: "ellipsis") }
                .buttonStyle(MapControlButtonStyle()).accessibilityLabel("Map controls")
            Button { followPlayer = true; focusRequest = MapFocusRequest(mode: .player) } label: { Image(systemName: "location.fill") }
                .buttonStyle(MapControlButtonStyle()).accessibilityLabel("Center player")
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
                            HStack(spacing: 8) {
                                if let mount = telemetry.latest?.mount.displayName {
                                    Label(mount, systemImage: "hare.fill").font(.caption2)
                                }
                                if telemetry.latest?.ui.inCombat == true {
                                    Label("Combat", systemImage: "flame.fill").font(.caption2).foregroundStyle(GWPalette.warning)
                                }
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
                            .buttonStyle(GWPrimaryButtonStyle())
                    }
                }
            }
            .padding(GWSpacing.medium).background(GWPalette.mapOverlay, in: RoundedRectangle(cornerRadius: GWSpacing.large))
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
                Text("Enable live position with the bridge running on your gaming PC.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Connect to PC") { showingPairing = true }.buttonStyle(.borderedProminent).tint(.orange)
            }.padding(14).background(GWPalette.mapOverlay, in: RoundedRectangle(cornerRadius: GWSpacing.large))
        case .connectedNoGW2: statusBanner("Connected to your PC. Launch Guild Wars 2 and enter the game.", symbol: "gamecontroller")
        case let .positionUnavailable(message): statusBanner(message, symbol: "location.slash")
        case .stale: statusBanner("Waiting for live position…", symbol: "clock.arrow.circlepath")
        case .disconnected: statusBanner("Can't reach your PC. Check the network, bridge, and Private-network firewall access.", symbol: "wifi.slash")
        case .connecting: statusBanner("Connecting to your gaming PC…", symbol: "arrow.triangle.2.circlepath")
        case .reconnecting: statusBanner("Connection lost. Reconnecting automatically…", symbol: "arrow.triangle.2.circlepath")
        case .pairingInvalid:
            VStack(spacing: 8) {
                statusBanner("The bridge pairing changed. Scan its QR code again.", symbol: "qrcode")
                Button("Pair again") { showingPairing = true }.buttonStyle(.borderedProminent).tint(.orange)
            }
        case let .protocolMismatch(message): statusBanner(message, symbol: "exclamationmark.arrow.triangle.2.circlepath")
        case .connectedLive: EmptyView()
        }
    }

    private var artworkAvailable: Bool {
        guard let metadata else { return true }
        return ArenaNetOfficialTileProvider().coverage(for: metadata).isOfficial
    }

    private var unavailableArtworkBanner: some View {
        Label("Detailed map artwork is not available from ArenaNet for this area.", systemImage: "map")
            .font(.caption2).foregroundStyle(.secondary)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityIdentifier("map.artwork.unavailable")
    }

    @ViewBuilder
    private var calibrationHUD: some View {
        let projection = ArenaNetTileProjection.shared
        let continentID = metadata?.continentId ?? 1
        let config = projection.configuration(continentID: continentID)
        let tileWorld = viewportTileWorld
            ?? projection.tileWorldCoordinate(from: viewportCenter, continentID: continentID, mapFloor: metadata?.defaultFloor ?? 1)
        VStack(alignment: .leading, spacing: 3) {
            Text("MAP CALIBRATION").font(.caption2.bold()).foregroundStyle(.secondary)
            Text("CURRENT CONTINENT  X: \(viewportCenter.x.formatted(.number.precision(.fractionLength(1))))  Y: \(viewportCenter.y.formatted(.number.precision(.fractionLength(1))))")
            if let tileWorld {
                Text("TILE WORLD  X: \(tileWorld.x.formatted(.number.precision(.fractionLength(1))))  Y: \(tileWorld.y.formatted(.number.precision(.fractionLength(1))))")
            }
            Text("EoD tile offset  X: \(config.usesLegacyTileOrigin ? Int(EndOfDragonsShift.deltaX) : 0)  Y: \(config.usesLegacyTileOrigin ? Int(EndOfDragonsShift.deltaY) : 0)")
            if let viewportTile {
                Text("Tile  z: \(viewportTile.zoom)  x: \(viewportTile.x)  y: \(viewportTile.y)")
            }
            Text("Map ID \(metadata?.id ?? telemetry.latest?.map?.id ?? -1)  continent \(continentID)  floor \(metadata?.defaultFloor ?? 1)")
            Text("API max zoom \(config.advertisedMaxZoom)  projection reference zoom \(config.referenceZoom)  user zoom \(viewportZoom)")
            let mode = MapDetailMode(rawValue: mapDetailRaw) ?? .balanced
            let viewport = MapViewportTransform(
                center: viewportCenter, zoom: viewportZoom, magnification: 1, dragOffset: .zero,
                size: CGSize(width: 390, height: 844), tileReferenceZoom: config.referenceZoom)
                .visibleContinentRect(marginPoints: 256)
            let sourceZoom = MapRasterDetail.sourceZoom(
                displayZoom: viewportZoom, continentID: continentID, viewport: viewport, mode: mode)
            Text("camera zoom \(viewportCameraZoom.formatted(.number.precision(.fractionLength(2))))  tile source \(viewportZoom)  source artwork zoom \(sourceZoom)  mode \(mode.title)")
            let comparison = MapDetailPolicy.comparison(
                objectives: objectives.visibleObjectives, displayZoom: viewportZoom,
                balancedSourceZoom: MapRasterDetail.sourceZoom(
                    displayZoom: viewportZoom, continentID: continentID, viewport: viewport, mode: .balanced),
                detailedSourceZoom: MapRasterDetail.sourceZoom(
                    displayZoom: viewportZoom, continentID: continentID, viewport: viewport, mode: .detailed),
                targetID: objectives.currentTargetID, routeIDs: Set(objectives.route?.objectives ?? []))
            Text(comparison.balanced.diagnosticsText(mode: .balanced))
            Text(comparison.detailed.diagnosticsText(mode: .detailed))
            Toggle("Tile debug grid", isOn: $showTileDebugGrid).font(.caption)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: GWSpacing.medium))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Map calibration overlay")
    }

    private func statusBanner(_ message: String, symbol: String) -> some View {
        Label(message, systemImage: symbol).font(.caption).padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: GWSpacing.medium))
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
        .background(.green.opacity(0.92), in: RoundedRectangle(cornerRadius: GWSpacing.medium))
    }

    private var statusColor: Color {
        switch telemetry.state {
        case .connectedLive: .green
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
            DeveloperDiagnostics.shared.mapSnapshot = MapQADiagnostics.snapshot(
                metadata: loadedMetadata,
                player: playerPoint,
                viewport: viewportCenter,
                userZoom: viewportZoom,
                tileWorld: viewportTileWorld,
                tile: viewportTile)
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
        configuration.label.font(.subheadline.bold()).padding(.horizontal, GWSpacing.medium).frame(minWidth: 44, minHeight: 44)
            .background(GWPalette.mapOverlay, in: Capsule()).opacity(configuration.isPressed ? 0.65 : 1)
    }
}
