import SwiftUI

struct MapMarkerCanvas: View {
    let markers: [MapSceneMarker]
    let transform: MapViewportTransform
    let visited: Set<String>
    let harvested: Set<String>
    let images: [URL: Image]
    var targetID: MapObjectiveID? = nil
    let onActivate: (MapSceneMarker) -> Void

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, _ in
            for marker in markers {
                draw(marker, in: &context, at: transform.screenPosition(for: marker.coordinate))
            }
        }
        .accessibilityRepresentation {
            ForEach(markers) { marker in
                Button(marker.accessibilityLabel(harvested: harvested)) { onActivate(marker) }
            }
        }
    }

    private func draw(_ marker: MapSceneMarker, in context: inout GraphicsContext, at point: CGPoint) {
        let rect = CGRect(x: point.x - 15.5, y: point.y - 15.5, width: 31, height: 31)
        var markerContext = context
        markerContext.opacity = opacity(for: marker)
        markerContext.addFilter(.shadow(color: .black.opacity(0.75), radius: 2))

        if let url = marker.officialIconURL, let image = images[url] {
            markerContext.draw(markerContext.resolve(image), in: rect)
        } else {
            markerContext.fill(Path(ellipseIn: rect), with: .color(.gray.opacity(0.92)))
            var fallback = markerContext.resolve(Image(systemName: marker.fallbackSymbol))
            fallback.shading = .color(.white)
            markerContext.draw(fallback, in: rect.insetBy(dx: 7, dy: 7))
        }

        if case let .gathering(node) = marker {
            let isVisited = visited.contains(node.id)
            markerContext.stroke(
                Path(ellipseIn: rect.insetBy(dx: 0.5, dy: 0.5)),
                with: .color(isVisited ? .yellow : .white.opacity(0.35)),
                lineWidth: isVisited ? 2 : 1)
        }
        if let objective = marker.objective {
            if objective.state == .visited || objective.state == .manuallyCompleted {
                markerContext.stroke(
                    Path(ellipseIn: rect.insetBy(dx: 1, dy: 1)),
                    with: .color(objective.state == .manuallyCompleted ? .green : .yellow), lineWidth: 2)
            }
            if targetID == objective.id {
                markerContext.stroke(
                    Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)),
                    with: .color(.cyan), lineWidth: 3)
            }
        }
    }

    private func opacity(for marker: MapSceneMarker) -> Double {
        switch marker {
        case let .gathering(node): return harvested.contains(node.id) ? 0.45 : 1
        case let .objective(objective):
            let gatheringID = objective.id.rawValue.replacingOccurrences(of: "gathering:", with: "")
            return harvested.contains(gatheringID) ? 0.45 : 1
        case .landmark: return 1
        }
    }
}
