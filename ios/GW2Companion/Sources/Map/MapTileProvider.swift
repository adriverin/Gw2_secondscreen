import Foundation

protocol MapTileProvider: Sendable {
    func tileURL(continent: Int, floor: Int, zoom: Int, x: Int, y: Int) -> URL?
}

struct ArenaNetTileProvider: MapTileProvider {
    var projection: ArenaNetTileProjection = .shared

    func tileURL(continent: Int, floor: Int, zoom: Int, x: Int, y: Int) -> URL? {
        // Reject out-of-range indices. Never wrap, modulo, or remainder the path.
        guard projection.tileWorldRect(for: TileIndex(zoom: zoom, x: x, y: y), continentID: continent) != nil else {
            return nil
        }
        return URL(string: "https://tiles.guildwars2.com/\(continent)/\(floor)/\(zoom)/\(x)/\(y).jpg")
    }
}
