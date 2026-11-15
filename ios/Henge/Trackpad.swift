import SwiftUI
import UIKit

/// A surface that works like a Mac's trackpad — it is one: the engine presents it on
/// the Mac's USB bus as a Magic Trackpad 2, so the Mac's own multitouch engine sees
/// the fingers: two scroll, three swipe between Spaces and to Mission Control, four
/// show the session's hidden controls.
///
/// Clicking depends on the input mode (Settings > Trackpad):
///  - Touchscreen: the surface itself clicks. A quick tap is a left click, a quick
///    two-finger tap is a right click, and touching then holding presses the button
///    down so moving drags. These go out as mouse buttons alongside the pad's fingers.
///  - Volume buttons: the surface only points and gestures; the clicks live on the
///    volume keys (VolumeClicks), so a tap here does nothing.
/// Only fingers count: a real trackpad or mouse goes through HardwareMouse.
/// Synthesizes Magic Trackpad 2 multi-finger shortcut gestures on the USB bus so macOS
/// handles them through its native multitouch gesture engine.
enum TrackpadGestures {
    private static var activeTask: Task<Void, Never>?
    private static var activeCount = 0

    static func missionControl() {
        swipe3(dx: 0, startY: 3600, endY: 1400)
    }

    static func appExpose() {
        swipe3(dx: 0, startY: 1400, endY: 3600)
    }

    static func spaceLeft() {
        swipe3Horizontal(startX: 2400, endX: 5600)
    }

    static func spaceRight() {
        swipe3Horizontal(startX: 5600, endX: 2400)
    }

    static func showDesktop() {
        let cx = 4067, cy = 2603
        let starts = [(cx - 450, cy - 350), (cx + 450, cy - 350), (cx - 450, cy + 350), (cx + 450, cy + 350)]
        let ends   = [(cx - 2200, cy - 1700), (cx + 2200, cy - 1700), (cx - 2200, cy + 1700), (cx + 2200, cy + 1700)]
        runTrajectory(starts: starts, ends: ends)
    }

    static func launchpad() {
        let cx = 4067, cy = 2603
        let starts = [(cx - 2200, cy - 1700), (cx + 2200, cy - 1700), (cx - 2200, cy + 1700), (cx + 2200, cy + 1700)]
        let ends   = [(cx - 350, cy - 250), (cx + 350, cy - 250), (cx - 350, cy + 250), (cx + 350, cy + 250)]
        runTrajectory(starts: starts, ends: ends)
    }

    static func spotlight() {
        Keys.chord(Keys.command, " ")
    }

    private static func swipe3(dx: Int, startY: Int, endY: Int) {
        let cx = 4067
        let starts = [(cx - 700, startY), (cx, startY), (cx + 700, startY)]
        let ends   = [(cx - 700 + dx, endY), (cx + dx, endY), (cx + 700 + dx, endY)]
        runTrajectory(starts: starts, ends: ends)
    }

    private static func swipe3Horizontal(startX: Int, endX: Int) {
        let cy = 2603
        let starts = [(startX - 700, cy), (startX, cy), (startX + 700, cy)]
        let ends   = [(endX - 700, cy), (endX, cy), (endX + 700, cy)]
        runTrajectory(starts: starts, ends: ends)
    }

    private static func nowMs() -> UInt32 {
        let ms = UInt32(truncatingIfNeeded: Int(ProcessInfo.processInfo.systemUptime * 1000))
        return ms == 0 ? 1 : ms
    }

    private static func releaseActive() {
        guard activeCount > 0 else { return }
        let ts = nowMs()
        for i in 0..<activeCount {
            henge_vm_touch(Int32(11 + i), 2, 0, 0, ts)
        }
        activeCount = 0
    }

    private static func runTrajectory(starts: [(Int, Int)], ends: [(Int, Int)]) {
        activeTask?.cancel()
        releaseActive()
        let count = min(starts.count, ends.count)
        guard count > 0 else { return }
        activeTask = Task { @MainActor in
            activeCount = count
            var ts = nowMs()
            for i in 0..<count {
                henge_vm_touch(Int32(11 + i), 0, Int32(starts[i].0), Int32(starts[i].1), ts)
            }
            let steps = 12
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: 14_000_000)
                if Task.isCancelled { break }
                let t = Double(step) / Double(steps)
                let nextTs = nowMs()
                ts = nextTs > ts ? nextTs : ts &+ 1
                for i in 0..<count {
                    let x = Int32(Double(starts[i].0) + Double(ends[i].0 - starts[i].0) * t)
                    let y = Int32(Double(starts[i].1) + Double(ends[i].1 - starts[i].1) * t)
                    henge_vm_touch(Int32(11 + i), 1, x, y, ts)
                }
                henge_vm_touch_frame(ts)
            }
            releaseActive()
        }
    }
}

struct Trackpad: UIViewRepresentable {
    /// Four fingers tapped together: the session shows its hidden controls.
    static let revealTap = Notification.Name("henge.trackpad.revealTap")

    func makeUIView(context: Context) -> Surface { Surface() }
    func updateUIView(_ view: Surface, context: Context) {}

    final class Surface: UIView, UIPointerInteractionDelegate, UIGestureRecognizerDelegate {
        /// The emulated pad's sensor, in the Magic Trackpad 2's own units.
        private static let sensorW: Int32 = 8134
        private static let sensorH: Int32 = 5206
        private static let holdTime: TimeInterval = 0.4
        private static let tapTime: TimeInterval = 0.3
        private static let tapDistance: CGFloat = 8

        private struct Finger { var touch: UITouch; var id: Int32 }

        private var fingers: [Finger] = []
        private var freeIds = Set<Int32>(1...5) /* a touch screen reports five fingers at most */
        private var started = Date()
        private var travelled: CGFloat = 0
        private var mostFingers = 0
        private var touchesLogged = 0

        /* Indirect trackpad pinch/rotation state (uses finger IDs 9 and 10). */
        private lazy var pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        private lazy var rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        private var pinchActive = false
        private var pinchTriggered = false
        private var rotationActive = false

        /* Touchscreen-mode clicking. */
        private var holding = false
        private var holdTimer: Timer?
        private let buzz = UIImpactFeedbackGenerator(style: .medium)
        private var tapsClick: Bool { VolumeClicks.inputMode == .touchscreen }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            backgroundColor = .clear
            addInteraction(UIPointerInteraction(delegate: self))
            for g in [pinchGesture, rotationGesture] as [UIGestureRecognizer] {
                g.cancelsTouchesInView = false
                g.delaysTouchesBegan = false
                g.delaysTouchesEnded = false
                g.delegate = self
                addGestureRecognizer(g)
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            (gestureRecognizer === pinchGesture && otherGestureRecognizer === rotationGesture) ||
            (gestureRecognizer === rotationGesture && otherGestureRecognizer === pinchGesture)
        }

        /// Over the Mac there is only the Mac's pointer, if iPadOS hasn't locked its own away.
        func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? { .hidden() }

        required init?(coder: NSCoder) { fatalError("made in code") }

        /// Where the finger is on the pad's sensor, in its units.
        private func sensor(_ t: UITouch) -> (Int32, Int32) {
            let p = t.location(in: self)
            // One scale for both axes. The view and the pad's sensor are different
            // shapes, so stretching the view to fill the sensor would make a finger
            // move the pointer further on one axis than the other. Map the view to a
            // centred part of the sensor at a single scale instead.
            let w = max(Double(bounds.width), 1), h = max(Double(bounds.height), 1)
            let scale = min(Double(Self.sensorW) / w, Double(Self.sensorH) / h)
            let x = (Double(p.x) - w / 2) * scale + Double(Self.sensorW) / 2
            let y = (Double(p.y) - h / 2) * scale + Double(Self.sensorH) / 2
            return (Int32(min(max(x, 0), Double(Self.sensorW))),
                    Int32(min(max(y, 0), Double(Self.sensorH))))
        }

        /* A touch sample's own clock, in ms. The guest derives finger speed from the
           timestamp deltas, so reports must carry the sample time, not the moment we
           process the event -- otherwise a burst of samples reads as one enormous flick
           and scroll inertia goes wild on release. */
        private static func ms(_ t: TimeInterval) -> UInt32 {
            let v = UInt32(truncatingIfNeeded: Int(t * 1000))
            return v == 0 ? 1 : v
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            let touches = touches.filter { $0.type != .indirectPointer }
            guard !touches.isEmpty else { return }
            if fingers.isEmpty {
                started = Date()
                travelled = 0
                mostFingers = 0
                if tapsClick { buzz.prepare() }
            }
            for t in touches {
                guard let id = freeIds.min() else { break }
                freeIds.remove(id)
                fingers.append(Finger(touch: t, id: id))
                let (x, y) = sensor(t)
                henge_vm_touch(id, 0, x, y, Self.ms(t.timestamp))
                if touchesLogged < 12 {
                    touchesLogged += 1
                    HengeLog.log("input", "trackpad: finger \(id) down at \(x),\(y)")
                }
            }
            mostFingers = max(mostFingers, fingers.count)
            guard tapsClick else { return }
            if fingers.count >= 2 {
                cancelHold()
                if holding { /* a drag becomes a multi-finger gesture */
                    holding = false
                    henge_vm_mouse_button(0, 0)
                }
            } else {
                armHold()
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            var moved = false
            let ts = Self.ms(event?.timestamp ?? touches.first?.timestamp ?? 0)
            for t in touches where t.type != .indirectPointer {
                guard let i = fingers.firstIndex(where: { $0.touch == t }) else { continue }
                let now = t.location(in: self), before = t.previousLocation(in: self)
                travelled += abs(now.x - before.x) + abs(now.y - before.y)
                let (x, y) = sensor(t)
                henge_vm_touch(fingers[i].id, 1, x, y, ts)
                moved = true
            }
            /* Moving means pointing or a gesture, not a tap or a press-to-drag. */
            if tapsClick && travelled >= Self.tapDistance && !holding { cancelHold() }
            /* One frame with every finger that moved, so the guest sees a gesture's
               fingers move together rather than one at a time. */
            if moved { henge_vm_touch_frame(ts) }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }

        private func lift(_ touches: Set<UITouch>) {
            var lifted: [Int32] = []
            fingers.removeAll { finger in
                guard touches.contains(finger.touch), finger.touch.type != .indirectPointer else { return false }
                freeIds.insert(finger.id)
                lifted.append(finger.id)
                return true
            }
            guard !lifted.isEmpty else { return }
            let ts = Self.ms(touches.map(\.timestamp).max() ?? 0)
            for id in lifted { henge_vm_touch(id, 2, 0, 0, ts) }
            guard fingers.isEmpty else { return } /* fingers still down: the gesture goes on */
            /* The whole gesture is over. */
            if tapsClick {
                cancelHold()
                let quick = Date().timeIntervalSince(started) < Self.tapTime
                let still = travelled < Self.tapDistance
                if holding {
                    holding = false
                    henge_vm_mouse_button(0, 0) /* let go of the drag */
                } else if quick && still {
                    if mostFingers == 1 { click(0) }      /* a tap is a left click */
                    else if mostFingers == 2 { click(1) } /* a two-finger tap is a right click */
                }
            }
            if mostFingers >= 4, travelled < Self.tapDistance * 3, Date().timeIntervalSince(started) < Self.tapTime * 2 {
                NotificationCenter.default.post(name: Trackpad.revealTap, object: nil)
            }
            StickyKeys.shared.releaseAll()
        }

        /// A brief press of a mouse button: down then up.
        private func click(_ button: Int32) {
            henge_vm_mouse_button(button, 1)
            henge_vm_mouse_button(button, 0)
            buzz.impactOccurred()
        }

        /// A finger that stays put presses the left button down, so moving it drags.
        private func armHold() {
            cancelHold()
            let timer = Timer(timeInterval: Self.holdTime, repeats: false) { [weak self] _ in
                guard let self, self.fingers.count == 1, self.travelled < Self.tapDistance else { return }
                self.holding = true
                henge_vm_mouse_button(0, 1)
                self.buzz.impactOccurred()
            }
            RunLoop.main.add(timer, forMode: .common)
            holdTimer = timer
        }

        private func cancelHold() {
            holdTimer?.invalidate()
            holdTimer = nil
        }

        @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
            guard fingers.isEmpty else {
                if pinchActive { endPinch() }
                return
            }
            if g.state == .began {
                pinchTriggered = false
            }
            if HardwareKeys.isControlHeld || HardwareKeys.isOptionHeld {
                if pinchActive { endPinch() }
                if g.state == .changed && !pinchTriggered {
                    if g.scale < 0.78 {
                        pinchTriggered = true
                        HardwareKeys.suppressGestureModifiers()
                        TrackpadGestures.launchpad()
                    } else if g.scale > 1.28 {
                        pinchTriggered = true
                        HardwareKeys.suppressGestureModifiers()
                        TrackpadGestures.showDesktop()
                    }
                }
                if g.state == .ended || g.state == .cancelled || g.state == .failed {
                    pinchTriggered = false
                }
                return
            }
            let ts = Self.ms(ProcessInfo.processInfo.systemUptime)
            let s = Double(min(max(g.scale, 0.25), 3.0))
            let spanX = Int32(min(max(500.0 * s, 120.0), 3400.0))
            let spanY = Int32(min(max(350.0 * s, 80.0), 2200.0))
            switch g.state {
            case .began:
                pinchActive = true
                henge_vm_touch(9, 0, Self.sensorW / 2 - spanX, Self.sensorH / 2 - spanY, ts)
                henge_vm_touch(10, 0, Self.sensorW / 2 + spanX, Self.sensorH / 2 + spanY, ts)
            case .changed:
                guard pinchActive else { return }
                henge_vm_touch(9, 1, Self.sensorW / 2 - spanX, Self.sensorH / 2 - spanY, ts)
                henge_vm_touch(10, 1, Self.sensorW / 2 + spanX, Self.sensorH / 2 + spanY, ts)
                henge_vm_touch_frame(ts)
            case .ended, .cancelled, .failed:
                endPinch()
            default: break
            }
        }

        private func endPinch() {
            guard pinchActive else { return }
            pinchActive = false
            let ts = Self.ms(ProcessInfo.processInfo.systemUptime)
            henge_vm_touch(9, 2, 0, 0, ts)
            henge_vm_touch(10, 2, 0, 0, ts)
        }

        @objc private func handleRotation(_ g: UIRotationGestureRecognizer) {
            guard fingers.isEmpty, !pinchActive else {
                if rotationActive { endRotation() }
                return
            }
            let ts = Self.ms(ProcessInfo.processInfo.systemUptime)
            let radius = 800.0
            let angle = Double(g.rotation)
            let dx = Int32(radius * cos(angle))
            let dy = Int32(radius * sin(angle))
            switch g.state {
            case .began:
                rotationActive = true
                henge_vm_touch(9, 0, Self.sensorW / 2 - dx, Self.sensorH / 2 - dy, ts)
                henge_vm_touch(10, 0, Self.sensorW / 2 + dx, Self.sensorH / 2 + dy, ts)
            case .changed:
                guard rotationActive else { return }
                henge_vm_touch(9, 1, Self.sensorW / 2 - dx, Self.sensorH / 2 - dy, ts)
                henge_vm_touch(10, 1, Self.sensorW / 2 + dx, Self.sensorH / 2 + dy, ts)
                henge_vm_touch_frame(ts)
            case .ended, .cancelled, .failed:
                endRotation()
            default: break
            }
        }

        private func endRotation() {
            guard rotationActive else { return }
            rotationActive = false
            let ts = Self.ms(ProcessInfo.processInfo.systemUptime)
            henge_vm_touch(9, 2, 0, 0, ts)
            henge_vm_touch(10, 2, 0, 0, ts)
        }
    }
}

/// One mouse button you can hold: down when touched, up when let go.
struct MouseButton: View {
    let title: String
    let button: Int32
    @State private var down = false

    var body: some View {
        Text(title)
            .font(.system(size: 15))
            .foregroundStyle(down ? Desk.text : Desk.dim)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(down ? Desk.raised : Color.clear)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !down else { return }
                        down = true
                        henge_vm_mouse_button(button, 1)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .onEnded { _ in
                        down = false
                        henge_vm_mouse_button(button, 0)
                        StickyKeys.shared.releaseAll()
                    }
            )
            .accessibilityLabel(title)
    }
}