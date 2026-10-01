import CoreGraphics
import Foundation

enum MapArtworkCoverage: Equatable, Sendable {
    case officialTiles
    case unavailable(reason: String)

    var isOfficial: Bool {
        if case .officialTiles = self { return true }
        return false
    }
}

protocol MapArtworkProvider: Sendable {
    func coverage(for map: GW2MapMetadata) -> MapArtworkCoverage
    func tileURL(continent: Int, floor: Int, zoom: Int, x: Int, y: Int) -> URL?
}

struct ArenaNetOfficialTileProvider: MapArtworkProvider, MapTileProvider {
    var projection: ArenaNetTileProjection = .shared
    private let tiles = ArenaNetTileProvider()

    func coverage(for map: GW2MapMetadata) -> MapArtworkCoverage {
        if projection.mapHasPaintedArtwork(map) { return .officialTiles }
        return .unavailable(reason: "Detailed map artwork is not available from ArenaNet for this area.")
    }

    func tileURL(continent: Int, floor: Int, zoom: Int, x: Int, y: Int) -> URL? {
        tiles.tileURL(continent: continent, floor: floor, zoom: zoom, x: x, y: y)
    }
}

/// Neutral background when official tiles are absent. Future licensed modern-map
/// artwork would implement `MapArtworkProvider` separately; this app does not
/// scrape wiki or third-party map imagery.
struct NeutralFallbackProvider: MapArtworkProvider {
    func coverage(for map: GW2MapMetadata) -> MapArtworkCoverage {
        .unavailable(reason: "Detailed map artwork is not available from ArenaNet for this area.")
    }

    func tileURL(continent: Int, floor: Int, zoom: Int, x: Int, y: Int) -> URL? { nil }
}

enum MapDetailMode: String, CaseIterable, Identifiable, Sendable {
    case balanced
    case detailed

    var id: Self { self }
    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .detailed: "Detailed"
        }
    }

    /// Extra source zoom is Detailed-only. Balanced uses display zoom so the setting is visible.
    func sourceZoomBias(displayZoom: Int, referenceZoom: Int, visibleTileCountWithoutBias: Int) -> Int {
        guard self == .detailed else { return 0 }
        guard displayZoom >= 5, displayZoom < referenceZoom else { return 0 }
        if visibleTileCountWithoutBias > 40 { return 0 }
        return 1
    }

    /// Lowest zoom at which Detailed still keeps extra marker types that Balanced has already dropped.
    var markerCullZoom: Int {
        switch self {
        case .balanced: 6
        case .detailed: 4
        }
    }

    static let storageKey = "map.detail.mode"
}

enum MapRasterDetail {
    static let maxSupersampledTiles = 384
    static let maximumVisibleDerivedTiles = 48
    static let maximumDerivedSourceTiles = DirectDetailedTileProvider.maximumSourceTiles

    enum RenderingSource: Equatable, Sendable {
        case unavailable
        case native(zoom: Int)
        case overzoom(sourceZoom: Int)
    }

    static func renderingSource(
        displayZoom: Int,
        continentID: Int,
        mode: MapDetailMode,
        visibleDisplayTileCount: Int,
        artworkAvailable: Bool = true,
        projection: ArenaNetTileProjection = .shared
    ) -> RenderingSource {
        guard artworkAvailable else { return .unavailable }
        let reference = projection.configuration(continentID: continentID).referenceZoom
        let sourceFactor = 1 << max(0, reference - displayZoom)
        let sourceTileCount = visibleDisplayTileCount * sourceFactor * sourceFactor
        guard mode == .detailed,
              (displayZoom == 5 || displayZoom == 6),
              reference == 7,
              visibleDisplayTileCount <= maximumVisibleDerivedTiles,
              sourceTileCount <= maximumDerivedSourceTiles
        else { return .native(zoom: displayZoom) }
        return .overzoom(sourceZoom: reference)
    }

    static func sourceZoom(
        displayZoom: Int, continentID: Int, viewport: CGRect,
        mode: MapDetailMode, projection: ArenaNetTileProjection = .shared
    ) -> Int {
        let unbiased = projection.tiles(
            coveringContinentRect: viewport, zoom: displayZoom, continentID: continentID, mapFloor: 1)
        switch renderingSource(
            displayZoom: displayZoom, continentID: continentID, mode: mode,
            visibleDisplayTileCount: unbiased.count, projection: projection)
        {
        case .unavailable: return displayZoom
        case let .native(zoom): return zoom
        case let .overzoom(sourceZoom): return sourceZoom
        }
    }
}
