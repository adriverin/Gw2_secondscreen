import SwiftUI

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
    var onVisibleCoordinateChange: ((ContinentPoint, Int, TileWorldCoordinate?, TileIndex?) -> Void)? = nil

    private let projection = ArenaNetTileProjection.shared
    private let tileProvider: MapTileProvider = ArenaNetTileProvider()
    @ObservedObject private var iconStore = MapIconStore.shared
    @State private var center = ContinentPoint(x: 44_615.5, y: 29_863.7)
    @State private var zoom = 6
    @State private var markerScene = MapMarkerScene(objectives: [])
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var magnification = 1.0

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
            .gesture(panGesture.simultaneously(with: zoomGesture))
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    guard let objective = markerScene.marker(at: value.location, in: transform)?.objective else { return }
                    onSelectObjective(objective)
                })
            .onChange(of: sceneVersion, initial: true) { _, _ in
                markerScene = MapMarkerScene(objectives: objectives)
            }
            .task(id: iconRequestKey) { await iconStore.load(markerScene.iconURLs) }
            .onChange(of: player) { _, newPlayer in
                guard followPlayer, let newPlayer else { return }
                center = newPlayer
            }
            .onChange(of: metadata?.id) { _, _ in
                if let metadata, let bounds = metadata.continentBounds {
                    if followPlayer, let player {
                        center = player
                    } else {
                        fit(bounds, size: geometry.size)
                    }
                }
            }
            .onChange(of: focusRequest) { _, request in
                if let request { focus(request.mode, size: geometry.size) }
            }
            .onChange(of: center) { _, _ in reportVisibleCoordinate() }
            .onChange(of: zoom) { _, _ in reportVisibleCoordinate() }
            .onAppear { reportVisibleCoordinate() }
        }
    }

    @ViewBuilder
    private func tileLayer(transform: MapViewportTransform) -> some View {
        let viewport = transform.visibleContinentRect(marginPoints: 256 * magnification)
        let continentID = metadata?.continentId ?? 1
        let floor = metadata?.defaultFloor ?? 1
        let tileIDs = projection.tiles(
            coveringContinentRect: viewport, zoom: zoom, continentID: continentID, mapFloor: floor)

        ForEach(tileIDs, id: \.self) { tile in
            if let url = tileProvider.tileURL(
                continent: continentID, floor: floor, zoom: tile.zoom, x: tile.x, y: tile.y),
               let worldRect = projection.tileWorldRect(for: tile, continentID: continentID),
               let continent = projection.continentCoordinate(
                from: TileWorldCoordinate(x: worldRect.midX, y: worldRect.midY),
                continentID: continentID, mapFloor: floor) {
                MapTileImage(url: url, index: tile, showDebug: showTileDebugGrid)
                    .frame(width: tileScreenSize * magnification, height: tileScreenSize * magnification)
                    .position(transform.screenPosition(for: continent))
            }
        }
    }

    private var tileScreenSize: CGFloat { CGFloat(ArenaNetTileProjection.tileSize + 1) }

    private func markerCanvas(_ markers: [MapSceneMarker], transform: MapViewportTransform) -> some View {
        MapMarkerCanvas(
            markers: markers, transform: transform,
            visited: [], harvested: harvested, images: iconStore.images,
            targetID: target?.id, onActivate: { marker in
                if let objective = marker.objective { onSelectObjective(objective) }
            })
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
            center: center, zoom: zoom, magnification: magnification, dragOffset: dragOffset, size: size,
            tileReferenceZoom: tileReferenceZoom)
    }

    private var tileReferenceZoom: Int {
        projection.configuration(continentID: metadata?.continentId ?? 1).referenceZoom
    }

    private var iconRequestKey: String { markerScene.iconURLs.map(\.absoluteString).sorted().joined(separator: "|") }

    private var worldUnitsPerPixel: Double {
        projection.worldUnitsPerTilePixel(zoom: zoom, continentID: metadata?.continentId ?? 1)
    }

    private func renderableMarkers(_ markers: [MapSceneMarker]) -> [MapSceneMarker] {
        guard zoom <= 3 else { return Array(markers.prefix(700)) }
        return markers.filter {
            guard let objective = $0.objective else { return true }
            return objective.id == target?.id || objective.type == .waypoint || objective.type == .masteryInsight
        }.prefix(250).map { $0 }
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
                return
            }
        }
        zoom = 2
    }

    private func reportVisibleCoordinate() {
        let continentID = metadata?.continentId ?? 1
        let floor = metadata?.defaultFloor ?? 1
        let tileWorld = projection.tileWorldCoordinate(from: center, continentID: continentID, mapFloor: floor)
        let tile = tileWorld.flatMap { projection.tileIndex(from: $0, zoom: zoom, continentID: continentID) }
        onVisibleCoordinateChange?(center, zoom, tileWorld, tile)
    }

    private var panGesture: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in state = value.translation }
            .onChanged { _ in followPlayer = false }
            .onEnded { value in
                center = ContinentPoint(
                    x: center.x - value.translation.width * worldUnitsPerPixel / magnification,
                    y: center.y - value.translation.height * worldUnitsPerPixel / magnification)
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($magnification) { value, state, _ in state = value.magnification }
            .onEnded { value in
                if value.magnification > 1.25 { zoom = min(tileReferenceZoom, zoom + 1) }
                if value.magnification < 0.8 { zoom = max(2, zoom - 1) }
            }
    }
}

private struct MapTileImage: View {
    let url: URL
    let index: TileIndex
    let showDebug: Bool

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image.resizable()
            default:
                Rectangle().fill(Color.white.opacity(0.035))
                    .overlay(Rectangle().stroke(Color.white.opacity(0.04)))
            }
        }
        .overlay {
            if showDebug {
                VStack(spacing: 1) {
                    Text("z=\(index.zoom)")
                    Text("x=\(index.x)")
                    Text("y=\(index.y)")
                }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.yellow)
                .shadow(color: .black, radius: 1)
                .allowsHitTesting(false)
            }
        }
        .accessibilityHidden(true)
    }
}
