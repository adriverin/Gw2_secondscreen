import SwiftUI

private struct TileID: Hashable {
    let x: Int
    let y: Int
}

enum MapFocusMode: Equatable { case player, target, both, coordinate(ContinentPoint) }

struct MapFocusRequest: Equatable {
    let id = UUID()
    let mode: MapFocusMode
}

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
    let onSelectObjective: (MapObjective) -> Void

    private let tileProvider: MapTileProvider = ArenaNetTileProvider()
    @ObservedObject private var iconStore = MapIconStore.shared
    @State private var center = ContinentPoint(x: 44_615.5, y: 29_863.7)
    @State private var zoom = 7
    @State private var markerScene = MapMarkerScene(objectives: [])
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var magnification = 1.0

    var body: some View {
        GeometryReader { geometry in
            let transform = viewportTransform(size: geometry.size)
            let visibleMarkers = renderableMarkers(markerScene.visibleMarkers(in: transform))
            ZStack {
                Color(red: 0.10, green: 0.12, blue: 0.14)
                tileLayer(transform: transform)
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
            .onChange(of: focusRequest) { _, request in
                if let request { focus(request.mode, size: geometry.size) }
            }
        }
    }

    @ViewBuilder
    private func tileLayer(transform: MapViewportTransform) -> some View {
        let viewport = transform.visibleContinentRect(marginPoints: 256 * magnification)
        let minX = Int(floor(viewport.minX / worldUnitsPerPixel / 256))
        let maxX = Int(ceil(viewport.maxX / worldUnitsPerPixel / 256))
        let minY = Int(floor(viewport.minY / worldUnitsPerPixel / 256))
        let maxY = Int(ceil(viewport.maxY / worldUnitsPerPixel / 256))
        let tileIDs = (minY...maxY).flatMap { y in (minX...maxX).map { TileID(x: $0, y: y) } }

        ForEach(tileIDs, id: \.self) { tile in
            if let metadata,
               let url = tileProvider.tileURL(
                continent: metadata.continentId, floor: metadata.defaultFloor,
                zoom: zoom, x: tile.x, y: tile.y) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable() }
                    else { tilePlaceholder }
                }
                .frame(width: 257 * magnification, height: 257 * magnification)
                .position(transform.screenPosition(for: ContinentPoint(
                    x: (Double(tile.x * 256) + 128) * worldUnitsPerPixel,
                    y: (Double(tile.y * 256) + 128) * worldUnitsPerPixel)))
            }
        }
    }

    private var tilePlaceholder: some View {
        Rectangle().fill(Color.white.opacity(0.035)).overlay(Rectangle().stroke(Color.white.opacity(0.04)))
    }

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
        MapViewportTransform(center: center, zoom: zoom, magnification: magnification, dragOffset: dragOffset, size: size)
    }

    private var iconRequestKey: String { markerScene.iconURLs.map(\.absoluteString).sorted().joined(separator: "|") }
    private var worldUnitsPerPixel: Double { pow(2, Double(GW2CoordinateTransformer.maximumTileZoom - zoom)) }

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
            for candidate in stride(from: GW2CoordinateTransformer.maximumTileZoom, through: 2, by: -1) {
                let units = pow(2, Double(GW2CoordinateTransformer.maximumTileZoom - candidate))
                if dx <= Double(size.width) * units * 0.72 && dy <= Double(size.height) * units * 0.62 {
                    zoom = candidate
                    break
                }
            }
        case let .coordinate(point):
            center = point
            followPlayer = false
        }
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
                if value.magnification > 1.25 { zoom = min(GW2CoordinateTransformer.maximumTileZoom, zoom + 1) }
                if value.magnification < 0.8 { zoom = max(2, zoom - 1) }
            }
    }
}
