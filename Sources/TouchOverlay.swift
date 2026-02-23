import SwiftUI
import UIKit

struct TouchOverlayView: UIViewRepresentable {
    let laneCount: Int
    let onTouchDown: @MainActor (Int, CGFloat) -> Void
    let onTouchUp: @MainActor (Int) -> Void

    func makeUIView(context: Context) -> TouchCaptureView {
        let view = TouchCaptureView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.isExclusiveTouch = false
        view.laneCount = laneCount
        view.onTouchDown = onTouchDown
        view.onTouchUp = onTouchUp
        return view
    }

    func updateUIView(_ uiView: TouchCaptureView, context: Context) {
        uiView.laneCount = laneCount
        uiView.onTouchDown = onTouchDown
        uiView.onTouchUp = onTouchUp
    }
}

// UIView is @MainActor, so all touch methods run on main actor — no Task wrapper needed
final class TouchCaptureView: UIView {
    var laneCount: Int = 4
    var onTouchDown: (@MainActor (Int, CGFloat) -> Void)?
    var onTouchUp: (@MainActor (Int) -> Void)?

    private var touchLanes: [ObjectIdentifier: Int] = [:]

    private func laneFor(_ point: CGPoint) -> Int {
        let laneWidth = bounds.width / CGFloat(laneCount)
        return max(0, min(laneCount - 1, Int(point.x / laneWidth)))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            let lane = laneFor(point)
            touchLanes[ObjectIdentifier(touch)] = lane
            onTouchDown?(lane, point.y)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            if let lane = touchLanes.removeValue(forKey: id) {
                onTouchUp?(lane)
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            if let lane = touchLanes.removeValue(forKey: id) {
                onTouchUp?(lane)
            }
        }
    }
}
