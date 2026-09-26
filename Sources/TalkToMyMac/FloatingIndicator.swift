import AppKit
import Observation
import SwiftUI

// MARK: - Model

/// What the floating indicator is showing. Driven by `AppDelegate`'s `RecordingIndicator`
/// conformance, plus live input levels pushed from `AudioCapture` while recording.
@MainActor
@Observable
final class FloatingIndicatorModel {
    enum Phase: Equatable {
        /// App running, nothing happening: a small resting dot.
        case idle
        /// Mic is live: expands into a waveform of the input level.
        case recording
        /// Transcribing/formatting a finished recording.
        case processing
    }

    static let barCount = 24

    var phase: Phase = .idle
    /// Most recent input levels (0…1), oldest first — one per waveform bar.
    private(set) var levels = [Float](repeating: 0, count: barCount)

    func push(_ newLevels: [Float]) {
        levels.append(contentsOf: newLevels)
        levels.removeFirst(max(levels.count - Self.barCount, 0))
    }

    func resetLevels() {
        levels = [Float](repeating: 0, count: Self.barCount)
    }
}

extension FloatingIndicatorModel.Phase {
    /// Size of the visible capsule in each phase. Also the draggable area.
    var capsuleSize: CGSize {
        switch self {
        case .idle:       CGSize(width: 12, height: 12)
        case .recording:  CGSize(width: 148, height: 34)
        case .processing: CGSize(width: 34, height: 34)
        }
    }
}

// MARK: - Window

/// A small always-on-top overlay that shows the app is running, and grows into a live
/// waveform while recording. Sits at the bottom centre of the screen until dragged, after
/// which it stays wherever it was put (remembered across launches).
///
/// It's a borderless, non-activating panel, so it never steals focus from the app being
/// dictated into (which would break paste-at-cursor). It only accepts the mouse while the
/// pointer is over the visible capsule; the rest of the panel stays click-through.
@MainActor
final class FloatingIndicatorController: NSObject {
    let model = FloatingIndicatorModel()
    private let panel: NSPanel
    private var mouseMonitors: [Any] = []
    /// Set while we move the panel ourselves, so only user drags get saved as a position.
    private var isPlacingProgrammatically = false

    private static let panelSize = NSSize(width: 180, height: 50)
    /// Gap between the capsule and the bottom of the panel (room for its shadow).
    fileprivate static let capsuleBottomPadding: CGFloat = 6
    /// Gap between the indicator and the Dock (or screen edge, if the Dock is hidden).
    private static let bottomMargin: CGFloat = 8
    /// Extra grab area around the capsule — the idle dot alone is a tiny target.
    private static let hitSlop: CGFloat = 6
    private static let visibleKey = "floatingIndicatorVisible"
    private static let originKey = "floatingIndicatorOrigin"

    var isVisible: Bool {
        get { UserDefaults.standard.object(forKey: Self.visibleKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.visibleKey)
            applyVisibility()
        }
    }

    /// Where the user dragged the panel to; `nil` means "default spot on the active screen".
    private var savedOrigin: NSPoint? {
        get { UserDefaults.standard.string(forKey: Self.originKey).map(NSPointFromString) }
        set {
            if let newValue {
                UserDefaults.standard.set(NSStringFromPoint(newValue), forKey: Self.originKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.originKey)
            }
        }
    }

    override init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // the SwiftUI capsule draws its own
        // Above everything — normal and floating windows, the Dock, the menu bar, and open
        // menus — so it's never hidden. Safe because it's tiny and mostly click-through.
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Follow the user across Spaces and over full-screen apps.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let host = NSHostingView(rootView: FloatingIndicatorView(model: model))
        // The panel's size is fixed; don't let SwiftUI resize it as the capsule animates.
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: Self.panelSize)
        panel.contentView = host

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidMove),
            name: NSWindow.didMoveNotification,
            object: panel
        )
        installMouseMonitors()

        restorePosition()
        applyVisibility()
    }

    /// Re-centres on whichever screen the mouse is on, so the indicator appears where the
    /// user is working. Does nothing once the user has dragged it somewhere themselves.
    func moveToActiveScreen() {
        guard savedOrigin == nil else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        place(at: NSPoint(
            x: visible.midX - Self.panelSize.width / 2,
            y: visible.minY + Self.bottomMargin
        ))
    }

    /// Uses the dragged-to position if it's still on a connected screen; otherwise falls
    /// back to the default spot (e.g. the display it was on has been unplugged).
    private func restorePosition() {
        if let origin = savedOrigin, Self.isOnAnyScreen(origin) {
            place(at: origin)
        } else {
            savedOrigin = nil
            moveToActiveScreen()
        }
    }

    private func place(at origin: NSPoint) {
        isPlacingProgrammatically = true
        panel.setFrameOrigin(origin)
        isPlacingProgrammatically = false
    }

    /// Whether the resting dot would be visible on some screen with the panel at `origin`.
    private static func isOnAnyScreen(_ origin: NSPoint) -> Bool {
        let dotCentre = NSPoint(
            x: origin.x + panelSize.width / 2,
            y: origin.y + capsuleBottomPadding + FloatingIndicatorModel.Phase.idle.capsuleSize.height / 2
        )
        return NSScreen.screens.contains { $0.frame.contains(dotCentre) }
    }

    private func applyVisibility() {
        if isVisible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    // MARK: Dragging

    /// The capsule's current rect in screen coordinates, padded for easier grabbing.
    private var capsuleScreenRect: NSRect {
        let size = model.phase.capsuleSize
        let frame = panel.frame
        return NSRect(
            x: frame.midX - size.width / 2,
            y: frame.minY + Self.capsuleBottomPadding,
            width: size.width,
            height: size.height
        ).insetBy(dx: -Self.hitSlop, dy: -Self.hitSlop)
    }

    /// Makes the panel clickable only while the pointer is over the capsule. Global
    /// monitors see the pointer while it's over other apps; the local one sees it while
    /// it's over our own panel (and handles the drag itself).
    private func installMouseMonitors() {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            self?.updateClickThrough()
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown], handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseDown, event.window === self.panel {
                // Runs the system window-drag loop; `panelDidMove` saves where it lands.
                self.panel.performDrag(with: event)
                return nil
            }
            self.updateClickThrough()
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func updateClickThrough() {
        let overCapsule = capsuleScreenRect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == overCapsule {
            panel.ignoresMouseEvents = !overCapsule
        }
    }

    @objc private func panelDidMove() {
        guard !isPlacingProgrammatically else { return }
        savedOrigin = panel.frame.origin
    }

    @objc private func screenParametersChanged() {
        restorePosition()
    }
}

// MARK: - Views

private struct FloatingIndicatorView: View {
    let model: FloatingIndicatorModel

    var body: some View {
        ZStack {
            switch model.phase {
            case .idle:
                EmptyView()
            case .recording:
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    WaveformBars(levels: model.levels)
                }
                .transition(.opacity)
            case .processing:
                ProcessingSpinner()
                    .transition(.opacity)
            }
        }
        .frame(width: model.phase.capsuleSize.width, height: model.phase.capsuleSize.height)
        .background(Capsule().fill(.black.opacity(0.72)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        .animation(.spring(duration: 0.35, bounce: 0.25), value: model.phase)
        // Grow upward from the resting spot rather than from the panel's centre.
        .padding(.bottom, FloatingIndicatorController.capsuleBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

}

private struct WaveformBars: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(.white)
                    .frame(width: 2.5, height: 3 + CGFloat(levels[i]) * 19)
            }
        }
        .animation(.linear(duration: 0.08), value: levels)
    }
}

private struct ProcessingSpinner: View {
    var body: some View {
        TimelineView(.animation) { context in
            let turns = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 14, height: 14)
                .rotationEffect(.degrees(turns * 360))
        }
    }
}
