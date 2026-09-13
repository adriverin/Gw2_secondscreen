import CoreGraphics
import Foundation

struct MapViewportTransform: Equatable {
    let center: ContinentPoint
    let zoom: Int
    let magnification: Double
    let dragOffset: CGSize
    let size: CGSize

    var worldUnitsPerScreenPoint: Double {
        pow(2, Double(GW2CoordinateTransformer.maximumTileZoom - zoom)) / magnification
    }

    func screenPosition(for point: ContinentPoint) -> CGPoint {
        CGPoint(
            x: size.width / 2 + (point.x - center.x) / worldUnitsPerScreenPoint + dragOffset.width,
            y: size.height / 2 + (point.y - center.y) / worldUnitsPerScreenPoint + dragOffset.height)
    }

    func continentPoint(for screenPoint: CGPoint) -> ContinentPoint {
        ContinentPoint(
            x: center.x + (screenPoint.x - size.width / 2 - dragOffset.width) * worldUnitsPerScreenPoint,
            y: center.y + (screenPoint.y - size.height / 2 - dragOffset.height) * worldUnitsPerScreenPoint)
    }

    func visibleContinentRect(marginPoints: Double = 0) -> CGRect {
        let topLeft = continentPoint(for: CGPoint(x: -marginPoints, y: -marginPoints))
        let bottomRight = continentPoint(for: CGPoint(x: size.width + marginPoints, y: size.height + marginPoints))
        return CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y))
    }
}

enum MapSceneMarker: Identifiable, Equatable {
    case landmark(MapLandmark)
    case gathering(GatheringNode)
    case objective(MapObjective)

    var id: String {
        switch self {
        case let .landmark(value): "landmark:\(value.id)"
        case let .gathering(value): "gathering:\(value.id)"
        case let .objective(value): value.id.rawValue
        }
    }

    var coordinate: ContinentPoint {
        switch self {
        case let .landmark(value): value.coordinate
        case let .gathering(value): ContinentPoint(x: value.continentX, y: value.continentY)
        case let .objective(value): value.coordinate
        }
    }

    var officialIconURL: URL? {
        switch self {
        case let .landmark(value): value.kind.officialIconURL
        case let .gathering(value): value.category.officialIconURL
        case let .objective(value): value.type.officialIconURL
        }
    }

    var fallbackSymbol: String {
        switch self {
        case let .landmark(value): value.kind.symbol
        case let .gathering(value): value.category.symbol
        case let .objective(value): value.type.symbol
        }
    }

    func accessibilityLabel(harvested: Set<String>) -> String {
        switch self {
        case let .landmark(value): "\(value.name), \(value.kind.title)"
        case let .gathering(value):
            "\(value.name), possible location\(harvested.contains(value.id) ? ", marked harvested" : "")"
        case let .objective(value): "\(value.name), \(value.type.title), \(value.state.label)"
        }
    }

    var objective: MapObjective? {
        guard case let .objective(value) = self else { return nil }
        return value
    }
}

struct MapMarkerScene {
    private struct Cell: Hashable {
        let x: Int
        let y: Int
    }

    private static let cellSize = 512.0
    private let markers: [MapSceneMarker]
    private let buckets: [Cell: [Int]]

    init(landmarks: [MapLandmark] = [], gathering: [GatheringNode] = []) {
        markers = landmarks.map(MapSceneMarker.landmark) + gathering.map(MapSceneMarker.gathering)
        var indexed: [Cell: [Int]] = [:]
        for (index, marker) in markers.enumerated() {
            indexed[Self.cell(for: marker.coordinate), default: []].append(index)
        }
        buckets = indexed
    }

    init(objectives: [MapObjective]) {
        markers = objectives.map(MapSceneMarker.objective)
        var indexed: [Cell: [Int]] = [:]
        for (index, marker) in markers.enumerated() {
            indexed[Self.cell(for: marker.coordinate), default: []].append(index)
        }
        buckets = indexed
    }

    var iconURLs: Set<URL> { Set(markers.compactMap(\.officialIconURL)) }

    func visibleMarkers(in transform: MapViewportTransform, marginPoints: Double = 18) -> [MapSceneMarker] {
        markers(in: transform.visibleContinentRect(marginPoints: marginPoints))
    }

    func marker(at screenPoint: CGPoint,
                in transform: MapViewportTransform,
                touchRadius: Double = 22) -> MapSceneMarker? {
        let center = transform.continentPoint(for: screenPoint)
        let worldRadius = touchRadius * transform.worldUnitsPerScreenPoint
        let candidates = indexedMarkers(in: CGRect(
            x: center.x - worldRadius, y: center.y - worldRadius,
            width: worldRadius * 2, height: worldRadius * 2))

        return candidates
            .compactMap { index, marker -> (Int, MapSceneMarker, CGFloat)? in
                let position = transform.screenPosition(for: marker.coordinate)
                let distance = hypot(position.x - screenPoint.x, position.y - screenPoint.y)
                return distance <= touchRadius ? (index, marker, distance) : nil
            }
            .min { lhs, rhs in
                if abs(lhs.2 - rhs.2) > 0.001 { return lhs.2 < rhs.2 }
                return lhs.0 > rhs.0
            }?.1
    }

    private func markers(in rect: CGRect) -> [MapSceneMarker] {
        indexedMarkers(in: rect).map(\.1)
    }

    private func indexedMarkers(in rect: CGRect) -> [(Int, MapSceneMarker)] {
        let minX = Int(floor(rect.minX / Self.cellSize))
        let maxX = Int(floor(rect.maxX / Self.cellSize))
        let minY = Int(floor(rect.minY / Self.cellSize))
        let maxY = Int(floor(rect.maxY / Self.cellSize))
        var indices: [Int] = []
        for y in minY...maxY {
            for x in minX...maxX {
                indices.append(contentsOf: buckets[Cell(x: x, y: y)] ?? [])
            }
        }
        return indices.sorted().compactMap { index in
            let marker = markers[index]
            let point = marker.coordinate
            return rect.contains(CGPoint(x: point.x, y: point.y)) ? (index, marker) : nil
        }
    }

    private static func cell(for point: ContinentPoint) -> Cell {
        Cell(x: Int(floor(point.x / Self.cellSize)), y: Int(floor(point.y / Self.cellSize)))
    }
}
