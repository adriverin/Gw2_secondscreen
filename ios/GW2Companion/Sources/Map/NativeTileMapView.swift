import SwiftUI

private struct TileID: Hashable {
    let x: Int
    let y: Int
}

struct NativeTileMapView: View {
    let player: ContinentPoint?
    let heading: Double
    let metadata: GW2MapMetadata?
    let nodes: [GatheringNode]
    let visited: Set<String>
    @Binding var followPlayer: Bool
    let onToggleVisited: (String) -> Void

    private let tileProvider: MapTileProvider = ArenaNetTileProvider()
    @State private var center = ContinentPoint(x: 15_710, y: 13_370)
    @State private var zoom = 6
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var magnification = 1.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.10, green: 0.12, blue: 0.14)
                tileLayer(size: geometry.size)
                ForEach(nodes) { node in marker(node, size: geometry.size) }
                if let player { playerMarker(player, size: geometry.size) }
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(panGesture.simultaneously(with: zoomGesture))
            .onChange(of: player) { _, newPlayer in
                guard followPlayer, let newPlayer else { return }
                withAnimation(.linear(duration: 0.08)) { center = newPlayer }
            }
        }
        .accessibilityLabel("Guild Wars 2 live map")
    }

    @ViewBuilder
    private func tileLayer(size: CGSize) -> some View {
        let centerPixelX = center.x / worldUnitsPerPixel
        let centerPixelY = center.y / worldUnitsPerPixel
        let minX = Int(floor((centerPixelX - size.width / (2 * magnification)) / 256)) - 1
        let maxX = Int(ceil((centerPixelX + size.width / (2 * magnification)) / 256)) + 1
        let minY = Int(floor((centerPixelY - size.height / (2 * magnification)) / 256)) - 1
        let maxY = Int(ceil((centerPixelY + size.height / (2 * magnification)) / 256)) + 1
        let tileIDs = (minY...maxY).flatMap { y in (minX...maxX).map { TileID(x: $0, y: y) } }

        ForEach(tileIDs, id: \.self) { tile in
            if let metadata,
               let url = tileProvider.tileURL(continent: metadata.continentId, floor: metadata.defaultFloor,
                                                zoom: zoom, x: tile.x, y: tile.y) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable() }
                    else { tilePlaceholder }
                }
                .frame(width: 257, height: 257)
                .position(
                    x: size.width / 2 + (Double(tile.x * 256) + 128 - centerPixelX) * magnification + dragOffset.width,
                    y: size.height / 2 + (Double(tile.y * 256) + 128 - centerPixelY) * magnification + dragOffset.height)
            }
        }
    }

    private var tilePlaceholder: some View {
        Rectangle().fill(Color.white.opacity(0.035)).overlay(Rectangle().stroke(Color.white.opacity(0.04)))
    }

    private func marker(_ node: GatheringNode, size: CGSize) -> some View {
        let position = screenPosition(ContinentPoint(x: node.continentX, y: node.continentY), size: size)
        return Button { onToggleVisited(node.id) } label: {
            Image(systemName: node.category.symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(node.reliability == .possible ? .orange : .white)
                .padding(7)
                .background(nodeColor(node).opacity(visited.contains(node.id) ? 0.25 : 0.92), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(node.reliability == .fixed ? 0.75 : 0.3), lineWidth: 1))
                .opacity(visited.contains(node.id) ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .position(position)
        .accessibilityLabel("\(node.name), \(node.reliability.title) location")
    }

    private func playerMarker(_ point: ContinentPoint, size: CGSize) -> some View {
        Image(systemName: "location.north.fill")
            .font(.system(size: 25, weight: .black))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.8), radius: 3)
            .rotationEffect(.radians(heading))
            .position(screenPosition(point, size: size))
            .animation(.linear(duration: 0.08), value: point)
            .accessibilityLabel("Current player position")
    }

    private func screenPosition(_ point: ContinentPoint, size: CGSize) -> CGPoint {
        let scale = worldUnitsPerPixel / magnification
        return CGPoint(
            x: size.width / 2 + (point.x - center.x) / scale + dragOffset.width,
            y: size.height / 2 + (point.y - center.y) / scale + dragOffset.height)
    }

    private var worldUnitsPerPixel: Double { pow(2, Double(GW2CoordinateTransformer.maximumTileZoom - zoom)) }

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
                if value.magnification > 1.25 { zoom = min(7, zoom + 1) }
                if value.magnification < 0.8 { zoom = max(2, zoom - 1) }
            }
    }

    private func nodeColor(_ node: GatheringNode) -> Color {
        switch node.category {
        case .ore: .gray
        case .wood: .brown
        case .plant: .green
        case .other: .blue
        }
    }
}
