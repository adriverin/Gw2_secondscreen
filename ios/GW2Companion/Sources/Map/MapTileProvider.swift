import Foundation

protocol MapTileProvider: Sendable {
    func tileURL(continent: Int, floor: Int, zoom: Int, x: Int, y: Int) -> URL?
}

struct ArenaNetTileProvider: MapTileProvider {
    func tileURL(continent: Int, floor: Int, zoom: Int, x: Int, y: Int) -> URL? {
        guard (0...7).contains(zoom), x >= 0, y >= 0 else { return nil }
        return URL(string: "https://tiles.guildwars2.com/\(continent)/\(floor)/\(zoom)/\(x)/\(y).jpg")
    }
}
