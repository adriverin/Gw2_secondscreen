import CoreGraphics
import Foundation

struct MapQADiagnosticsSnapshot: Codable, Equatable, Sendable {
    var mapID: Int?
    var mapName: String?
    var continentID: Int?
    var floor: Int?
    var continentX: Double?
    var continentY: Double?
    var tileWorldX: Double?
    var tileWorldY: Double?
    var referenceZoom: Int?
    var userZoom: Int?
    var tileZ: Int?
    var tileX: Int?
    var tileY: Int?
    var artworkAvailable: Bool
    var coverageReason: TileCoverageReason
    var playerContinentX: Double?
    var playerContinentY: Double?
    var visibleTileCount: Int?
    var visibleMarkerCount: Int?
    var sourceZoomBias: Int?

    init(
        mapID: Int? = nil,
        mapName: String? = nil,
        continentID: Int? = nil,
        floor: Int? = nil,
        continentX: Double? = nil,
        continentY: Double? = nil,
        tileWorldX: Double? = nil,
        tileWorldY: Double? = nil,
        referenceZoom: Int? = nil,
        userZoom: Int? = nil,
        tileZ: Int? = nil,
        tileX: Int? = nil,
        tileY: Int? = nil,
        artworkAvailable: Bool = false,
        coverageReason: TileCoverageReason = .mapMetadataMissing,
        playerContinentX: Double? = nil,
        playerContinentY: Double? = nil,
        visibleTileCount: Int? = nil,
        visibleMarkerCount: Int? = nil,
        sourceZoomBias: Int? = nil
    ) {
        self.mapID = mapID
        self.mapName = mapName
        self.continentID = continentID
        self.floor = floor
        self.continentX = continentX
        self.continentY = continentY
        self.tileWorldX = tileWorldX
        self.tileWorldY = tileWorldY
        self.referenceZoom = referenceZoom
        self.userZoom = userZoom
        self.tileZ = tileZ
        self.tileX = tileX
        self.tileY = tileY
        self.artworkAvailable = artworkAvailable
        self.coverageReason = coverageReason
        self.playerContinentX = playerContinentX
        self.playerContinentY = playerContinentY
        self.visibleTileCount = visibleTileCount
        self.visibleMarkerCount = visibleMarkerCount
        self.sourceZoomBias = sourceZoomBias
    }

    func redacted() -> MapQADiagnosticsSnapshot { self }

    var diagnosticsText: String {
        """
        Map ID: \(mapID.map(String.init) ?? "—")
        Map name: \(mapName ?? "—")
        continent ID: \(continentID.map(String.init) ?? "—")
        floor: \(floor.map(String.init) ?? "—")
        Current continent X/Y: \(fmt(continentX)) / \(fmt(continentY))
        Tile-world X/Y: \(fmt(tileWorldX)) / \(fmt(tileWorldY))
        Reference zoom: \(referenceZoom.map(String.init) ?? "—")
        User zoom: \(userZoom.map(String.init) ?? "—")
        Current tile z/x/y: \(tileZ.map(String.init) ?? "—") / \(tileX.map(String.init) ?? "—") / \(tileY.map(String.init) ?? "—")
        Tile coverage state: \(coverageReason.title)
        Artwork available: \(artworkAvailable ? "yes" : "no")
        Official tile artwork: \(artworkAvailable ? "Available" : "unavailable")
        Reason: \(coverageReason.title)
        Visible tiles: \(visibleTileCount.map(String.init) ?? "—")
        Visible markers: \(visibleMarkerCount.map(String.init) ?? "—")
        Source zoom bias: \(sourceZoomBias.map(String.init) ?? "—")
        """
    }

    private func fmt(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(2)))
    }
}

enum MapQADiagnostics {
    static func snapshot(
        metadata: GW2MapMetadata?,
        player: ContinentPoint?,
        viewport: ContinentPoint?,
        userZoom: Int?,
        tileWorld: TileWorldCoordinate?,
        tile: TileIndex?,
        visibleTileCount: Int? = nil,
        visibleMarkerCount: Int? = nil,
        sourceZoomBias: Int? = nil,
        projection: ArenaNetTileProjection = .shared
    ) -> MapQADiagnosticsSnapshot {
        let continentID = metadata?.continentId ?? 1
        let floor = metadata?.defaultFloor ?? 1
        let config = projection.configuration(continentID: continentID)
        let focus = player ?? viewport
        let resolvedTileWorld = tileWorld ?? focus.flatMap {
            projection.tileWorldCoordinate(from: $0, continentID: continentID, mapFloor: floor)
        }
        let zoom = userZoom ?? config.referenceZoom
        let resolvedTile = tile ?? resolvedTileWorld.flatMap {
            projection.tileIndex(from: $0, zoom: zoom, continentID: continentID)
        }
        let coverage = coverage(metadata: metadata, tile: resolvedTile)
        return MapQADiagnosticsSnapshot(
            mapID: metadata?.id,
            mapName: metadata?.name,
            continentID: continentID,
            floor: floor,
            continentX: focus?.x,
            continentY: focus?.y,
            tileWorldX: resolvedTileWorld?.x,
            tileWorldY: resolvedTileWorld?.y,
            referenceZoom: config.referenceZoom,
            userZoom: userZoom,
            tileZ: resolvedTile?.zoom,
            tileX: resolvedTile?.x,
            tileY: resolvedTile?.y,
            artworkAvailable: coverage.available,
            coverageReason: coverage.reason,
            playerContinentX: player?.x,
            playerContinentY: player?.y,
            visibleTileCount: visibleTileCount,
            visibleMarkerCount: visibleMarkerCount,
            sourceZoomBias: sourceZoomBias)
    }

    static func coverage(metadata: GW2MapMetadata?, tile: TileIndex?) -> (available: Bool, reason: TileCoverageReason) {
        guard let metadata else { return (false, .mapMetadataMissing) }
        guard ArenaNetTileProjection.shared.mapHasPaintedArtwork(metadata) else {
            return (false, .outsideKnownPaintedCoverage)
        }
        if tile == nil { return (false, .tileUnavailable) }
        return (true, .withinKnownPaintedCoverage)
    }
}

struct MapAlignmentMeasurement: Equatable, Sendable {
    var player: ContinentPoint
    var landmark: ContinentPoint
    var dx: Double
    var dy: Double
    var distance: Double
    var playerTile: TileWorldCoordinate
    var landmarkTile: TileWorldCoordinate
    var tile: TileIndex?
    var visuallyOverlapsSuggestion: Bool

    static let visualOverlapHint = 75.0

    static func measure(
        player: ContinentPoint,
        landmark: ContinentPoint,
        continentID: Int = 1,
        floor: Int = 1,
        projection: ArenaNetTileProjection = .shared
    ) -> MapAlignmentMeasurement {
        let dx = player.x - landmark.x
        let dy = player.y - landmark.y
        let distance = ObjectiveDistanceEngine.distance(from: player, to: landmark)
        let playerTile = projection.tileWorldCoordinate(from: player, continentID: continentID, mapFloor: floor)
            ?? TileWorldCoordinate(x: player.x, y: player.y)
        let landmarkTile = projection.tileWorldCoordinate(from: landmark, continentID: continentID, mapFloor: floor)
            ?? TileWorldCoordinate(x: landmark.x, y: landmark.y)
        let zoom = projection.configuration(continentID: continentID).referenceZoom
        let tile = projection.tileIndex(from: playerTile, zoom: zoom, continentID: continentID)
        return MapAlignmentMeasurement(
            player: player, landmark: landmark, dx: dx, dy: dy, distance: distance,
            playerTile: playerTile, landmarkTile: landmarkTile, tile: tile,
            visuallyOverlapsSuggestion: distance <= visualOverlapHint)
    }
}
