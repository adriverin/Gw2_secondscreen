import SwiftUI
import UIKit

struct MapFocusRequest: Equatable {
    let id = UUID()
    let mode: MapFocusMode
}

enum MapFocusMode: Equatable { case player, target, both, coordinate(ContinentPoint), mapBounds }

struct NativeTileMapView: View {
    let player: ContinentPoint?
    let heading: Double
    let metadata: GW2MapMetadata?
    let objectives: [MapObjective]
    let sceneVersion: Int
    let harvested: Set<String>
    let target: MapObjective?
    @Binding var followPlayer: Bool
    let focusRequest: MapFocusRequest?
    var showTileDebugGrid: Bool = false
    var showTiles: Bool = true
    let onSelectObjective: (MapObjective) -> Void
    var onBackgroundTap: (() -> Void)? = nil
    var routeIDs: Set<MapObjectiveID> = []
    var onVisibleCoordinateChange: ((ContinentPoint, Int, TileWorldCoordinate?, TileIndex?, Int, Int, Double) -> Void)? = nil

    private let projection = ArenaNetTileProjection.shared
    private let tileProvider: MapArtworkProvider = ArenaNetOfficialTileProvider()
    @ObservedObject private var iconStore = MapIconStore.shared
    @AppStorage(MapDetailMode.storageKey) private var mapDetailRaw = MapDetailMode.balanced.rawValue
    @State private var center = ContinentPoint(x: 44_615.5, y: 29_863.7)
    @State private var zoom = 6
    @State private var cameraZoom = 6.0
    @State private var pinch: ContinuousMapCamera.Pinch?
    @State private var markerScene = MapMarkerScene(objectives: [])
    @State private var dragOffset: CGSize = .zero
    @State private var lastVisibleTileCount = 0
    @State private var lastViewportSize = CGSize(width: 390, height: 844)
    @State private var layers = MapRasterLayerHandoff()
    @State private var backingFrame: MapRasterLayerFrame?
    private var activeFrame: MapRasterLayerFrame? { layers.active }
    private var outgoingFrame: MapRasterLayerFrame? { layers.outgoing }
    @State private var replacementOpacity = 1.0

    private var mapDetail: MapDetailMode { MapDetailMode(rawValue: mapDetailRaw) ?? .balanced }

    var body: some View {
        GeometryReader { geometry in
            let transform = viewportTransform(size: geometry.size)
            let visibleMarkers = renderableMarkers(markerScene.visibleMarkers(in: transform))
            ZStack {
                Color(red: 0.10, green: 0.12, blue: 0.14)
                if showTiles { tileLayer(transform: transform) }
                targetVector(transform: transform)
                markerCanvas(visibleMarkers, transform: transform)
                if let player { playerMarker(player, transform: transform) }
                if let target { offscreenTarget(target, transform: transform, size: geometry.size) }
            }
            .clipped()
            .contentShape(Rectangle())
            .overlay {
                MapGestureSurface(
                    cameraZoom: cameraZoom, sourceZoom: zoom,
                    onPan: { translation, ended in
                        guard pinch == nil else { dragOffset = .zero; return }
                        followPlayer = false
                        if ended {
                            center = ContinentPoint(x: center.x - translation.width * worldUnitsPerPixel,
                                                    y: center.y - translation.height * worldUnitsPerPixel)
                            dragOffset = .zero
                        } else { dragOffset = translation }
                    },
                    onPinch: { scale, anchor, began, ended in
                        if began || pinch == nil {
                            pinch = ContinuousMapCamera.Pinch(startZoom: cameraZoom, screenAnchor: anchor,
                                                             continentAnchor: viewportTransform(size: geometry.size).continentPoint(for: anchor))
                            dragOffset = .zero
                        }
                        followPlayer = false
                        if let update = pinch?.update(magnification: scale, size: geometry.size,
                                                      referenceZoom: tileReferenceZoom, movingAnchor: anchor) {
                            cameraZoom = update.zoom
                            center = update.center
                        }
                        if ended { pinch = nil }
                    },
                    onTap: { handleTap($0, transform: viewportTransform(size: geometry.size)) })
            }
            .onChange(of: sceneVersion, initial: true) { _, _ in
                markerScene = MapMarkerScene(objectives: objectives)
            }
            .task(id: iconRequestKey) { await iconStore.load(markerScene.iconURLs) }
            .onChange(of: player) { _, newPlayer in
                guard followPlayer, let newPlayer else { return }
                center = newPlayer
            }
            .onChange(of: metadata?.id) { _, _ in
                cameraZoom = min(Double(tileReferenceZoom), max(2, cameraZoom))
                zoom = min(tileReferenceZoom, max(2, zoom))
                if let metadata, let bounds = metadata.continentBounds {
                    if followPlayer, let player {
                        center = player
                    } else {
                        fit(bounds, size: geometry.size)
                    }
                }
                Task { await MapTileImageCache.shared.handleMemoryPressure() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                Task { await DerivedDetailedTileProvider.shared.handleMemoryPressure() }
            }
            .onChange(of: focusRequest) { _, request in
                if let request { focus(request.mode, size: geometry.size) }
            }
            .onChange(of: center) { _, _ in reportVisibleCoordinate() }
            .onChange(of: zoom) { _, _ in reportVisibleCoordinate() }
            .onChange(of: cameraZoom) { _, value in
                zoom = ContinuousMapCamera.sourceZoom(cameraZoom: value, current: zoom, maximum: tileReferenceZoom)
                reportVisibleCoordinate()
            }
            .onChange(of: mapDetailRaw) { _, _ in reportVisibleCoordinate() }
            .onChange(of: geometry.size) { _, size in
                lastViewportSize = size
                reportVisibleCoordinate()
            }
            .onAppear {
                lastViewportSize = geometry.size
                reportVisibleCoordinate()
            }
        }
    }

    @ViewBuilder
    private func tileLayer(transform: MapViewportTransform) -> some View {
        // One source-level border, bounded by the cold leaf budget. The request
        // changes only at a source threshold or tile boundary, not each frame.
        let margin = zoom == 4 ? 0 : 256 * ContinuousMapCamera.scale(cameraZoom: cameraZoom, sourceZoom: zoom)
        let viewport = transform.visibleContinentRect(marginPoints: margin)
        let continentID = metadata?.continentId ?? 1
        let floor = metadata?.defaultFloor ?? 1
        let paddedTiles = projection.tiles(
            coveringContinentRect: viewport, zoom: zoom, continentID: continentID, mapFloor: floor)
        // Promotion is gated ONLY by visible coverage. Prefetch is independent.
        let tileIDs = projection.tiles(coveringContinentRect: transform.visibleContinentRect(), zoom: zoom,
                                      continentID: continentID, mapFloor: floor)
        let candidate = MapRasterLayerRequest(continent: continentID, floor: floor, tiles: tileIDs, detailed: true)
        let request = MapRasterLayerRequest(
            continent: continentID, floor: floor, tiles: tileIDs,
            detailed: mapDetail == .detailed && candidate.permitsDetailed)
        let backingRequest = MapRasterLayerRequest.backing(continent: continentID, floor: floor)
        let backingReady = backingFrame?.request == backingRequest
        ZStack {
            // Never draw progressively loaded placeholders under a retained
            // frame. The complete coarse mosaic covers newly exposed geography.
            if backingReady, let backingFrame {
                rasterTiles(backingFrame.request.tiles, images: backingFrame.images,
                            continentID: continentID, floor: floor, transform: transform)
            } else { ProgressView("Loading map artwork…") }
            if let outgoingFrame, outgoingFrame.request.continent == continentID && outgoingFrame.request.floor == floor {
                rasterTiles(outgoingFrame.request.tiles, images: outgoingFrame.images,
                            continentID: continentID, floor: floor, transform: transform)
                    .opacity(layers.outgoingOpacity(progress: replacementOpacity))
            }
            if let activeFrame, activeFrame.request.continent == continentID && activeFrame.request.floor == floor {
                rasterTiles(activeFrame.request.tiles, images: activeFrame.images,
                            continentID: continentID, floor: floor, transform: transform)
                    .opacity(layers.activeOpacity(progress: replacementOpacity))
            }
        }
        .task(id: backingRequest) {
            guard !backingReady else { return }
            // A transient failure retries without replacing any complete frame.
            while !Task.isCancelled {
                if let frame = await MapRasterLayerLoader.frame(for: backingRequest), !Task.isCancelled {
                    backingFrame = frame
                    return
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .onChange(of: request, initial: true) { _, request in
            layers.begin(request)
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { replacementOpacity = 1 }
        }
        .task(id: RasterLoadKey(request: request, backingReady: backingReady)) {
            guard backingReady, !Task.isCancelled else { return }
            if request.detailed {
                // Native readiness and pyramid generation proceed independently.
                // A slow cold z4 build cannot hold the camera at an obsolete level.
                async let detailed = MapRasterLayerLoader.frame(for: request)
                if activeFrame == nil || activeFrame?.request.tiles.first?.zoom != zoom
                    || activeFrame?.request.continent != continentID || activeFrame?.request.floor != floor {
                    let native = MapRasterLayerRequest(continent: continentID, floor: floor, tiles: tileIDs, detailed: false)
                    if let frame = await MapRasterLayerLoader.frame(for: native), !Task.isCancelled { display(frame, target: request) }
                }
                if let frame = await detailed, !Task.isCancelled { display(frame, target: request) }
                else if !Task.isCancelled {
                    // This also handles same-level Detailed failure, not only
                    // cold starts/source changes. Native is another whole frame.
                    let native = MapRasterLayerRequest(continent: continentID, floor: floor, tiles: tileIDs, detailed: false)
                    if let frame = await MapRasterLayerLoader.retryingNativeFrame(for: native), !Task.isCancelled { display(frame, target: request) }
                }
            } else {
                while !Task.isCancelled {
                    if let frame = await MapRasterLayerLoader.frame(for: request), !Task.isCancelled {
                        display(frame, target: request)
                        break
                    }
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
            // Cache warming must never delay the visible frame's promotion.
            if !Task.isCancelled, paddedTiles != tileIDs {
                let prefetch = MapRasterLayerRequest(continent: continentID, floor: floor, tiles: paddedTiles,
                                                    detailed: request.detailed)
                _ = await MapRasterLayerLoader.frame(for: prefetch)
            }
        }
        .onAppear { lastVisibleTileCount = tileIDs.count }
        .onChange(of: tileIDs.count) { _, count in lastVisibleTileCount = count }
    }

    @MainActor
    private func display(_ frame: MapRasterLayerFrame, target: MapRasterLayerRequest) {
        guard !Task.isCancelled, layers.accept(frame, for: target) else { return }
        replacementOpacity = 0
        withAnimation(.linear(duration: ContinuousMapCamera.crossfadeSeconds)) { replacementOpacity = 1 }
        // Cleanup must survive cancellation of the loading viewport task.
        // Request identity prevents an older fade from clearing a newer layer.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            layers.finish(frame.request)
        }
    }

    private struct RasterLoadKey: Equatable {
        let request: MapRasterLayerRequest
        let backingReady: Bool
    }

    private func rasterTiles(_ tiles: [TileIndex], images: [TileIndex: UIImage], continentID: Int,
                             floor: Int, transform: MapViewportTransform) -> some View {
        ForEach(tiles, id: \.self) { tile in
            if tileProvider.tileURL(continent: continentID, floor: floor, zoom: tile.zoom, x: tile.x, y: tile.y) != nil,
               let rect = projection.tileWorldRect(for: tile, continentID: continentID),
               let point = projection.continentCoordinate(from: TileWorldCoordinate(x: rect.midX, y: rect.midY),
                                                          continentID: continentID, mapFloor: floor) {
                let side = 256 * ContinuousMapCamera.scale(cameraZoom: cameraZoom, sourceZoom: tile.zoom)
                Group {
                    if let image = images[tile] { Image(uiImage: image).resizable().interpolation(.high) }
                    // Only complete frames reach this renderer. There is no
                    // per-tile asynchronous replacement or placeholder here.
                }
                .frame(width: side + 0.5, height: side + 0.5)
                .overlay { if showTileDebugGrid { MapTileDebugLabel(index: tile) } }
                .position(transform.screenPosition(for: point))
                .accessibilityHidden(true)
            }
        }
    }

    private var tileScreenSize: CGFloat { CGFloat(ArenaNetTileProjection.tileSize + 1) }

    private func markerCanvas(_ markers: [MapSceneMarker], transform: MapViewportTransform) -> some View {
        MapMarkerCanvas(
            markers: markers, transform: transform,
            visited: [], harvested: harvested, images: iconStore.images,
            targetID: target?.id, appearances: markerAppearances(markers),
            onActivate: { marker in
                if let objective = marker.objective { onSelectObjective(objective) }
            })
    }

    private func markerAppearances(_ markers: [MapSceneMarker]) -> [String: MapMarkerAppearance] {
        Dictionary(uniqueKeysWithValues: markers.compactMap { marker in
            guard let objective = marker.objective else { return nil }
            return (marker.id, MapDetailPolicy.appearance(
                for: objective, mode: mapDetail, cameraZoom: cameraZoom, targetID: target?.id, routeIDs: routeIDs))
        })
    }

    private func handleTap(_ location: CGPoint, transform: MapViewportTransform) {
        guard pinch == nil, dragOffset == .zero else { return }
        if let objective = markerScene.marker(at: location, in: transform)?.objective {
            onSelectObjective(objective)
            return
        }
        if let player {
            let playerPoint = transform.screenPosition(for: player)
            if hypot(playerPoint.x - location.x, playerPoint.y - location.y) <= 28 {
                return
            }
        }
        onBackgroundTap?()
    }

    @ViewBuilder
    private func targetVector(transform: MapViewportTransform) -> some View {
        if let player, let target {
            Canvas { context, _ in
                let start = transform.screenPosition(for: player)
                let end = transform.screenPosition(for: target.coordinate)
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: .color(.cyan.opacity(0.72)), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                context.fill(Path(ellipseIn: CGRect(x: end.x - 7, y: end.y - 7, width: 14, height: 14)), with: .color(.cyan))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func offscreenTarget(_ target: MapObjective, transform: MapViewportTransform, size: CGSize) -> some View {
        let position = transform.screenPosition(for: target.coordinate)
        if position.x < 24 || position.y < 70 || position.x > size.width - 24 || position.y > size.height - 24 {
            let x = min(max(position.x, 54), size.width - 54)
            let y = min(max(position.y, 92), size.height - 54)
            let angle = atan2(position.y - size.height / 2, position.x - size.width / 2) + .pi / 2
            VStack(spacing: 2) {
                Image(systemName: "location.north.fill").rotationEffect(.radians(angle))
                Text(target.type.title).lineLimit(1).font(.caption2.bold())
            }
            .foregroundStyle(.cyan)
            .padding(7)
            .background(.ultraThinMaterial, in: Capsule())
            .position(x: x, y: y)
            .allowsHitTesting(false)
            .accessibilityLabel("Target off screen, \(target.name)")
        }
    }

    private func playerMarker(_ point: ContinentPoint, transform: MapViewportTransform) -> some View {
        Image(systemName: "location.north.fill")
            .font(.system(size: 25, weight: .black))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.8), radius: 3)
            .rotationEffect(.radians(heading))
            .position(transform.screenPosition(for: point))
            .animation(.linear(duration: 0.04), value: point)
            .accessibilityLabel("Current player position")
    }

    private func viewportTransform(size: CGSize) -> MapViewportTransform {
        MapViewportTransform(
            center: center, zoom: zoom, magnification: 1, dragOffset: pinch == nil ? dragOffset : .zero, size: size,
            tileReferenceZoom: tileReferenceZoom, cameraZoom: cameraZoom)
    }

    private var tileReferenceZoom: Int {
        projection.configuration(continentID: metadata?.continentId ?? 1).referenceZoom
    }

    private var iconRequestKey: String { markerScene.iconURLs.map(\.absoluteString).sorted().joined(separator: "|") }

    private var worldUnitsPerPixel: Double {
        pow(2, Double(tileReferenceZoom) - cameraZoom)
    }

    private func renderableMarkers(_ markers: [MapSceneMarker]) -> [MapSceneMarker] {
        markers.filter { marker in
            guard let objective = marker.objective else { return true }
            return MapDetailPolicy.appearance(
                for: objective, mode: mapDetail, cameraZoom: cameraZoom,
                targetID: target?.id, routeIDs: routeIDs).visible
        }.prefix(700).map { $0 }
    }

    private func focus(_ mode: MapFocusMode, size: CGSize) {
        switch mode {
        case .player:
            guard let player else { return }
            center = player
            followPlayer = true
        case .target:
            guard let target else { return }
            center = target.coordinate
            followPlayer = false
        case .both:
            guard let player, let target else { return }
            followPlayer = false
            center = ContinentPoint(x: (player.x + target.continentX) / 2, y: (player.y + target.continentY) / 2)
            let dx = abs(player.x - target.continentX)
            let dy = abs(player.y - target.continentY)
            for candidate in stride(from: tileReferenceZoom, through: 2, by: -1) {
                let units = projection.worldUnitsPerTilePixel(zoom: candidate, continentID: metadata?.continentId ?? 1)
                if dx <= Double(size.width) * units * 0.72 && dy <= Double(size.height) * units * 0.62 {
                    zoom = candidate
                    cameraZoom = Double(candidate)
                    break
                }
            }
        case let .coordinate(point):
            center = point
            followPlayer = false
        case .mapBounds:
            guard let bounds = metadata?.continentBounds else { return }
            followPlayer = false
            fit(bounds, size: size)
        }
    }

    private func fit(_ bounds: CGRect, size: CGSize) {
        center = ContinentPoint(x: bounds.midX, y: bounds.midY)
        for candidate in stride(from: tileReferenceZoom, through: 2, by: -1) {
            let units = projection.worldUnitsPerTilePixel(zoom: candidate, continentID: metadata?.continentId ?? 1)
            if bounds.width <= Double(size.width) * units * 0.92 && bounds.height <= Double(size.height) * units * 0.92 {
                zoom = candidate
                cameraZoom = Double(candidate)
                return
            }
        }
        zoom = 2
        cameraZoom = 2
    }

    private func reportVisibleCoordinate() {
        let continentID = metadata?.continentId ?? 1
        let floor = metadata?.defaultFloor ?? 1
        let tileWorld = projection.tileWorldCoordinate(from: center, continentID: continentID, mapFloor: floor)
        let tile = tileWorld.flatMap { projection.tileIndex(from: $0, zoom: zoom, continentID: continentID) }
        let transform = MapViewportTransform(
            center: center, zoom: zoom, magnification: 1, dragOffset: .zero, size: lastViewportSize,
            tileReferenceZoom: tileReferenceZoom, cameraZoom: cameraZoom)
        let margin = zoom == 4 ? 0 : 256 * ContinuousMapCamera.scale(cameraZoom: cameraZoom, sourceZoom: zoom)
        let viewport = transform.visibleContinentRect(marginPoints: margin)
        lastVisibleTileCount = projection.tiles(
            coveringContinentRect: viewport, zoom: zoom, continentID: continentID, mapFloor: floor).count
        let markerCount = renderableMarkers(markerScene.visibleMarkers(in: transform)).count
        onVisibleCoordinateChange?(center, zoom, tileWorld, tile, lastVisibleTileCount, markerCount, cameraZoom)
    }

}

private struct MapTileDebugLabel: View {
    let index: TileIndex

    var body: some View {
        VStack(spacing: 1) {
            Text("z=\(index.zoom)")
            Text("x=\(index.x)")
            Text("y=\(index.y)")
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(.yellow)
        .shadow(color: .black, radius: 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
