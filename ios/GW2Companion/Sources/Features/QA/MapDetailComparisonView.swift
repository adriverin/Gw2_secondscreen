import SwiftUI

struct MapDetailComparisonView: View {
    @State private var displayZoom = 6
    @State private var balanced: UIImage?
    @State private var detailed: UIImage?
    @State private var diagnostics: DerivedTileDiagnostics?

    private var displayTile: TileIndex {
        // Both samples cover Kessex Hills around Kessex Haven Waypoint.
        displayZoom == 6
            ? TileIndex(zoom: 6, x: 87, y: 61)
            : TileIndex(zoom: 5, x: 43, y: 30)
    }

    private var request: DerivedDetailedTileRequest {
        DerivedDetailedTileRequest(
            continent: 1, floor: 1, displayTile: displayTile, sourceZoom: 7)
    }

    var body: some View {
        List {
            Section {
                Picker("Display zoom", selection: $displayZoom) {
                    Text("z6 • 4 sources").tag(6)
                    Text("z5 • 16 sources").tag(5)
                }
                .pickerStyle(.segmented)
                Text("The two tiles cover the same display area. Balanced asks ArenaNet for the native lower-zoom tile. Detailed composites the z7 children and downsamples once.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Kessex A/B") {
                HStack(alignment: .top, spacing: 12) {
                    sample(title: "BALANCED", subtitle: "z\(displayZoom) native", image: balanced)
                    sample(title: "DETAILED", subtitle: "derived from z7", image: detailed)
                }
                .frame(maxWidth: .infinity)
            }
            Section("Derived tile diagnostics") {
                LabeledContent("Source tile count", value: "\(diagnostics?.sourceTileCount ?? request.sourceTileCount)")
                LabeledContent("Cache", value: diagnostics?.cacheState.rawValue ?? "loading")
                LabeledContent("Generation", value: diagnostics.map { "\($0.generationMilliseconds) ms" } ?? "—")
                LabeledContent("Image memory", value: diagnostics.map {
                    ByteCountFormatter.string(fromByteCount: Int64($0.imageMemoryBytes), countStyle: .memory)
                } ?? "—")
                LabeledContent("Mean RGB difference", value: differenceText)
                Text("A non-zero RGB difference confirms distinct raster sources; physical QA should still judge label and terrain granularity at the same viewport and zoom.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Limits") {
                LabeledContent("Simultaneous source fetches", value: "\(DerivedDetailedTileProvider.maximumSimultaneousSourceFetches)")
                LabeledContent("Derived generation tasks", value: "\(DerivedDetailedTileProvider.maximumDerivedGenerationTasks)")
                LabeledContent("Visible derived tiles", value: "\(MapRasterDetail.maximumVisibleDerivedTiles)")
                LabeledContent("Memory cache tiles", value: "\(DerivedDetailedTileProvider.memoryCountLimit)")
                LabeledContent("Disk cache files", value: "\(DerivedDetailedTileProvider.diskFileLimit)")
            }
        }
        .navigationTitle("Map Detail Comparison")
        .task(id: displayZoom) { await load() }
        .accessibilityIdentifier("qa.mapDetailComparison")
    }

    private func sample(title: String, subtitle: String, image: UIImage?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            Group {
                if let image {
                    Image(uiImage: image).resizable().interpolation(.high).aspectRatio(1, contentMode: .fit)
                } else {
                    Rectangle().fill(.quaternary).aspectRatio(1, contentMode: .fit).overlay { ProgressView() }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var differenceText: String {
        guard let balanced, let detailed,
              let delta = MapImageDifference.meanAbsoluteRGBDelta(balanced, detailed) else { return "—" }
        return delta.formatted(.number.precision(.fractionLength(2))) + "%"
    }

    private func load() async {
        balanced = nil
        detailed = nil
        diagnostics = nil
        let provider = ArenaNetTileProvider()
        guard let nativeURL = provider.tileURL(
            continent: 1, floor: 1, zoom: displayTile.zoom,
            x: displayTile.x, y: displayTile.y)
        else { return }
        async let native = MapTileImageCache.shared.image(for: nativeURL)
        async let derived = DerivedDetailedTileProvider.shared.image(for: request)
        let values = await (native, derived)
        guard !Task.isCancelled else { return }
        balanced = values.0
        detailed = values.1?.image
        diagnostics = values.1?.diagnostics
    }
}
