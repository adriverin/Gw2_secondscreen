import Foundation

/// Official current-continent landmarks used to lock tile artwork to overlay space.
enum MapAlignmentLandmarks {
    struct Landmark: Equatable, Sendable {
        var name: String
        var mapID: Int
        var mapName: String
        var kind: MapLandmarkKind
        var continent: ContinentCoordinate
        var continentID: Int
        var floor: Int
        /// Empirically verified zoom-7 tile that contains this landmark's artwork.
        var expectedTile: TileIndex
    }

    static let queensdaleContinentRect: [[Double]] = [[42_624, 28_032], [46_208, 30_464]]
    static let kessexHillsContinentRect: [[Double]] = [[42_112, 30_464], [46_208, 32_512]]
    static let sparkflyFenContinentRect: [[Double]] = [[48_000, 35_456], [50_560, 38_784]]
    static let lionsArchContinentRect: [[Double]] = [[48_000, 30_720], [50_432, 32_256]]

    static let shaemoorWaypoint = Landmark(
        name: "Shaemoor Waypoint", mapID: 15, mapName: "Queensdale", kind: .waypoint,
        continent: ContinentCoordinate(x: 43_728.4, y: 28_589.9),
        continentID: 1, floor: 1, expectedTile: TileIndex(zoom: 7, x: 170, y: 111))

    static let villageOfShaemoor = Landmark(
        name: "Village of Shaemoor", mapID: 15, mapName: "Queensdale", kind: .pointOfInterest,
        continent: ContinentCoordinate(x: 44_808.0, y: 29_894.0),
        continentID: 1, floor: 1, expectedTile: TileIndex(zoom: 7, x: 175, y: 116))

    static let queensdaleVista = Landmark(
        name: "Queensdale Vista", mapID: 15, mapName: "Queensdale", kind: .vista,
        continent: ContinentCoordinate(x: 44_688.0, y: 29_794.0),
        continentID: 1, floor: 1, expectedTile: TileIndex(zoom: 7, x: 174, y: 116))

    static let kessexHavenWaypoint = Landmark(
        name: "Kessex Haven Waypoint", mapID: 23, mapName: "Kessex Hills", kind: .waypoint,
        continent: ContinentCoordinate(x: 44_843.0, y: 31_380.9),
        continentID: 1, floor: 1, expectedTile: TileIndex(zoom: 7, x: 175, y: 122))

    static let garenhoff = Landmark(
        name: "Garenhoff", mapID: 23, mapName: "Kessex Hills", kind: .pointOfInterest,
        continent: ContinentCoordinate(x: 46_100.6, y: 32_018.3),
        continentID: 1, floor: 1, expectedTile: TileIndex(zoom: 7, x: 180, y: 125))

    static let kessexVista = Landmark(
        name: "Kessex Hills Vista", mapID: 23, mapName: "Kessex Hills", kind: .vista,
        continent: ContinentCoordinate(x: 44_987.2, y: 31_568.3),
        continentID: 1, floor: 1, expectedTile: TileIndex(zoom: 7, x: 175, y: 123))

    static let oceansGulletWaypoint = Landmark(
        name: "Ocean's Gullet Waypoint", mapID: 53, mapName: "Sparkfly Fen", kind: .waypoint,
        continent: ContinentCoordinate(x: 49_000.0, y: 36_500.0),
        continentID: 1, floor: 1, expectedTile: TileIndex(zoom: 7, x: 191, y: 142))

    static let lionsArchCenter = Landmark(
        name: "Lion's Arch", mapID: 50, mapName: "Lion's Arch", kind: .pointOfInterest,
        continent: ContinentCoordinate(x: 49_216.0, y: 31_488.0),
        continentID: 1, floor: 1, expectedTile: TileIndex(zoom: 7, x: 192, y: 123))

    static let coreTyria: [Landmark] = [
        shaemoorWaypoint, villageOfShaemoor, queensdaleVista,
        kessexHavenWaypoint, garenhoff, kessexVista,
        oceansGulletWaypoint, lionsArchCenter
    ]

    static func metadata(mapID: Int, name: String, continentRect: [[Double]]) -> GW2MapMetadata {
        GW2MapMetadata(
            id: mapID, name: name, continentId: 1, defaultFloor: 1,
            mapRect: [[0, 0], [1, 1]], continentRect: continentRect)
    }

    static let queensdaleMetadata = metadata(
        mapID: 15, name: "Queensdale", continentRect: queensdaleContinentRect)
    static let kessexHillsMetadata = metadata(
        mapID: 23, name: "Kessex Hills", continentRect: kessexHillsContinentRect)
    static let sparkflyFenMetadata = metadata(
        mapID: 53, name: "Sparkfly Fen", continentRect: sparkflyFenContinentRect)
    static let lionsArchMetadata = metadata(
        mapID: 50, name: "Lion's Arch", continentRect: lionsArchContinentRect)

    /// A post-artwork map whose current continent rectangle sits outside the
    /// official painted Core Tyria tile coverage.
    static let unsupportedNewMapMetadata = GW2MapMetadata(
        id: 9_999, name: "Unsupported Expansion Map", continentId: 1, defaultFloor: 1,
        mapRect: [[0, 0], [1, 1]],
        continentRect: [[8_000, 90_000], [12_000, 94_000]])
}
