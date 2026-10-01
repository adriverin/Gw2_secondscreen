import SwiftUI

struct MapDetailComparisonView: View {
    @State private var displayZoom = 6
    @State private var balanced: UIImage?
    @State private var detailed: DirectDetailedTileFrame?

    private var displayTile: TileIndex {
        displayZoom == 6 ? TileIndex(zoom: 6, x: 87, y: 61) : TileIndex(zoom: 5, x: 43, y: 30)
    }
    private var sourceTiles: [TileIndex] {
        DerivedDetailedTileRequest(continent: 1, floor: 1, displayTile: displayTile, sourceZoom: 7).sourceTiles() ?? []
    }

    var body: some View {
        List {
            Section {
                Picker("Display zoom", selection: $displayZoom) {
                    Text("z6 • 4 sources").tag(6)
                    Text("z5 • 16 sources").tag(5)
                }.pickerStyle(.segmented)
                Text("Same Kessex area: native lower-zoom artwork versus original z7 tiles drawn directly. No intermediate mosaic enters the live map.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Kessex A/B") {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading) {
                        Text("BALANCED").font(.caption.bold())
                        if let balanced {
                            Image(uiImage: balanced).resizable().aspectRatio(1, contentMode: .fit)
                        } else { placeholder }
                        Text("z\(displayZoom) native").font(.caption2)
                    }
                    VStack(alignment: .leading) {
                        Text("DETAILED").font(.caption.bold())
                        GeometryReader { geometry in
                            if let detailed, detailed.isComplete {
                                let factor = 1 << (7 - displayZoom)
                                let side = geometry.size.width / CGFloat(factor)
                                ZStack(alignment: .topLeading) {
                                    ForEach(Array(sourceTiles.enumerated()), id: \.element) { index, tile in
                                        if let image = detailed.images[tile] {
                                            Image(uiImage: image).resizable().interpolation(.high)
                                                .frame(width: side, height: side)
                                                .offset(x: CGFloat(index % factor) * side, y: CGFloat(index / factor) * side)
                                        }
                                    }
                                }
                            } else { placeholder }
                        }.aspectRatio(1, contentMode: .fit)
                        Text("Original z7 grid").font(.caption2)
                    }
                }
            }
            Section("Direct tile diagnostics") {
                LabeledContent("Source tile count", value: "\(sourceTiles.count)")
                LabeledContent("Frame", value: detailed?.isComplete == true ? "Complete" : "Loading / native fallback")
                LabeledContent("Source screen size", value: "\(Int(DirectDetailedTileLayout.screenSide(displayZoom: displayZoom))) px")
                Text("Inspect roads, rivers, and settlements on both sides of every child boundary. A mean RGB difference is not a geographical correctness test.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Limits") {
                LabeledContent("Source tile limit", value: "\(DirectDetailedTileProvider.maximumSourceTiles)")
                LabeledContent("Simultaneous fetches", value: "\(DirectDetailedTileProvider.maximumSimultaneousFetches)")
                LabeledContent("Memory cache tiles", value: "\(MapTileImageCache.memoryCountLimit)")
                Text("A failed, cancelled, or over-budget frame uses native artwork. Original source tiles reuse the memory/disk cache.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Map Detail Comparison")
        .task(id: displayZoom) { await load() }
        .accessibilityIdentifier("qa.mapDetailComparison")
    }

    private var placeholder: some View {
        Rectangle().fill(.quaternary).aspectRatio(1, contentMode: .fit).overlay { ProgressView() }
    }

    private func load() async {
        balanced = nil; detailed = nil
        guard let url = ArenaNetTileProvider().tileURL(continent: 1, floor: 1,
            zoom: displayTile.zoom, x: displayTile.x, y: displayTile.y) else { return }
        async let native = MapTileImageCache.shared.image(for: url)
        async let frame = DirectDetailedTileProvider.shared.frame(for:
            DirectDetailedTileRequest(continent: 1, floor: 1, tiles: sourceTiles))
        let values = await (native, frame)
        guard !Task.isCancelled else { return }
        balanced = values.0; detailed = values.1
    }
}
