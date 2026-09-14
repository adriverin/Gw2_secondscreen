import SwiftUI

/// Developer-only visual check: official tiles plus a known POI must overlap.
struct MapAlignmentHarnessView: View {
    var landmark: MapAlignmentLandmarks.Landmark = MapAlignmentLandmarks.kessexHavenWaypoint
    var metadata: GW2MapMetadata = MapAlignmentLandmarks.kessexHillsMetadata

    @State private var followPlayer = false

    var body: some View {
        VStack(spacing: 0) {
            NativeTileMapView(
                player: landmark.continent,
                heading: 0,
                metadata: metadata,
                objectives: [objective],
                sceneVersion: 1,
                harvested: [],
                target: objective,
                followPlayer: $followPlayer,
                focusRequest: MapFocusRequest(mode: .coordinate(landmark.continent)),
                showTileDebugGrid: true,
                showTiles: true,
                onSelectObjective: { _ in })
            .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 6) {
                Text(landmark.mapName).font(.headline)
                Text("\(landmark.kind.title) • \(landmark.name)")
                    .font(.subheadline)
                Text("Continent \(landmark.continent.x.formatted(.number.precision(.fractionLength(1)))), \(landmark.continent.y.formatted(.number.precision(.fractionLength(1))))")
                    .font(.caption.monospaced())
                Text("Expected tile z=\(landmark.expectedTile.zoom) x=\(landmark.expectedTile.x) y=\(landmark.expectedTile.y)")
                    .font(.caption.monospaced())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Alignment Harness")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Alignment harness for \(landmark.mapName), \(landmark.name)")
    }

    private var objective: MapObjective {
        MapObjective(
            id: MapObjectiveID("alignment:\(landmark.mapID):\(landmark.name)"),
            mapId: landmark.mapID, name: landmark.name,
            type: landmark.kind == .waypoint ? .waypoint : landmark.kind == .vista ? .vista : .landmark,
            continentX: landmark.continent.x, continentY: landmark.continent.y,
            source: .arenaNet, chatLink: nil, level: nil, description: nil, state: .unknown)
    }
}
