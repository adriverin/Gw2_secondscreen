import SwiftUI
import UIKit

/// UIKit supplies the live two-finger centroid (SwiftUI's startAnchor does not
/// follow moving fingers). Single-finger pan cannot also commit a pinch drag.
struct MapGestureSurface: UIViewRepresentable {
    var cameraZoom: Double
    var sourceZoom: Int
    var onPan: (CGSize, Bool) -> Void
    var onPinch: (Double, CGPoint, Bool, Bool) -> Void
    var onTap: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "map.camera"
        view.accessibilityLabel = "Map camera"
        view.accessibilityTraits = .allowsDirectInteraction
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        pan.delegate = context.coordinator
        pinch.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: pan)
        tap.require(toFail: pinch)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
        view.accessibilityValue = String(format: "Camera zoom %.3f; tile source %d", cameraZoom, sourceZoom)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: MapGestureSurface
        private var lastAnchor: CGPoint = .zero
        private var pinchInProgress = false
        private var suppressPanUntilEnd = false
        init(_ parent: MapGestureSurface) { self.parent = parent }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard [.began, .changed, .ended, .cancelled].contains(gesture.state) else { return }
            if gesture.state == .began && !pinchInProgress { suppressPanUntilEnd = false }
            if suppressPanUntilEnd {
                if [.ended, .cancelled].contains(gesture.state) { suppressPanUntilEnd = false }
                return
            }
            let point = gesture.translation(in: gesture.view)
            parent.onPan(CGSize(width: point.x, height: point.y), [.ended, .cancelled, .failed].contains(gesture.state))
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard [.began, .changed, .ended, .cancelled].contains(gesture.state) else { return }
            if gesture.state == .began { pinchInProgress = true; suppressPanUntilEnd = true }
            if [.ended, .cancelled].contains(gesture.state) { pinchInProgress = false }
            // Ended recognizers can have no touches, in which case location is
            // not a valid centroid. Retain the final two-finger location.
            if gesture.numberOfTouches >= 2 { lastAnchor = gesture.location(in: gesture.view) }
            parent.onPinch(gesture.scale, lastAnchor, gesture.state == .began,
                           [.ended, .cancelled, .failed].contains(gesture.state))
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer)
                || (gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer)
        }
        @objc func tap(_ gesture: UITapGestureRecognizer) {
            if gesture.state == .ended { parent.onTap(gesture.location(in: gesture.view)) }
        }
    }
}
