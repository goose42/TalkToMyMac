import AppKit
import Observation
import SwiftUI
import TalkToMyMacCore

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

    /// Dictionary replacements in the last paste that the user can still undo, and which
    /// occurrences (indices into `review.occurrences`) they've put back. While set, the idle dot becomes a pill showing the count.
    private(set) var review: ReplacementReview?
    private(set) var reverted: Set<Int> = []
    var isPickerOpen = false
    /// True while the text hasn't been pasted yet and the picker is waiting for Paste or
    /// Cancel; false when it's offering to fix a paste that already happened.
    private(set) var isBeforePaste = false

    /// The pasted text as it currently reads, given the user's choices.
    var currentText: String? { review?.text(reverting: reverted) }

    func show(_ review: ReplacementReview, beforePaste: Bool = false) {
        self.review = review
        reverted = []
        isBeforePaste = beforePaste
        isPickerOpen = beforePaste
    }

    func clearReview() {
        review = nil
        reverted = []
        isBeforePaste = false
        isPickerOpen = false
    }

    func setReverted(_ occurrence: Int, _ isReverted: Bool) {
        if isReverted { reverted.insert(occurrence) } else { reverted.remove(occurrence) }
    }

    /// Size of the visible capsule right now. Also the draggable area.
    var capsuleSize: CGSize {
        phase == .idle && review != nil ? CGSize(width: 28, height: 20) : phase.capsuleSize
    }
}

extension FloatingIndicatorModel.Phase {
    /// Size of the visible capsule in each phase, without a replacement review.
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
///
/// After a paste with dictionary replacements, clicking the capsule (without dragging) opens
/// a picker above it for putting back the words actually spoken. The offer lasts until the
/// user types or clicks in another app, since either could move the cursor away from the
/// pasted text.
///
/// For terminals, where a paste can't be fixed afterwards, the picker instead opens before
/// pasting, with Paste and Cancel buttons (see `askBeforePaste`).
@MainActor
final class FloatingIndicatorController: NSObject {
    let model = FloatingIndicatorModel()
    /// Rewrites the pasted text from the first string to the second in the app it went
    /// into. Returns false if it couldn't, which ends the review.
    var rewritePaste: ((String, String) -> Bool)?
    private let panel: NSPanel
    private let pickerPanel: NSPanel
    /// Resumes the paused pipeline with the text to paste, or nil to paste nothing.
    private var pendingPaste: ((String?) -> Void)?
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
        pickerPanel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        pickerPanel.isOpaque = false
        pickerPanel.backgroundColor = .clear
        pickerPanel.hasShadow = false
        pickerPanel.level = .screenSaver
        pickerPanel.hidesOnDeactivate = false
        pickerPanel.isReleasedWhenClosed = false

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
        pickerPanel.collectionBehavior = panel.collectionBehavior

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

    /// Offers `review` from the indicator. Ignored while the indicator is hidden.
    func showReview(_ review: ReplacementReview) {
        guard isVisible else { return }
        model.show(review)
        updatePicker()
    }

    /// Opens the picker for `review` before anything is pasted, and calls `completion` with
    /// the chosen text on Paste, or nil on Cancel or if a new recording starts first.
    func askBeforePaste(_ review: ReplacementReview, completion: @escaping (String?) -> Void) {
        finishPendingPaste(paste: false)
        pendingPaste = completion
        model.show(review, beforePaste: true)
        updatePicker()
    }

    /// Ends the review; one still waiting to paste is cancelled.
    func clearReview() {
        guard pendingPaste == nil else {
            finishPendingPaste(paste: false)
            return
        }
        model.clearReview()
        updatePicker()
    }

    private func finishPendingPaste(paste: Bool) {
        guard let completion = pendingPaste else { return }
        pendingPaste = nil
        let text = paste ? model.currentText : nil
        model.clearReview()
        updatePicker()
        completion(text)
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
        let size = model.capsuleSize
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
                // Runs the system window-drag loop until the mouse is released; `panelDidMove`
                // saves where it lands. A press that didn't move it is a click.
                let origin = self.panel.frame.origin
                self.panel.performDrag(with: event)
                if self.panel.frame.origin == origin, self.model.review != nil, !self.model.isBeforePaste {
                    self.model.isPickerOpen.toggle()
                    self.updatePicker()
                }
                return nil
            }
            self.updateClickThrough()
            return event
        }) {
            mouseMonitors.append(local)
        }
        // Global monitors only see events bound for other apps, so any of these means the
        // user is working there again. Our own synthesized keystrokes are tagged and skipped.
        if let other = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            // Nothing's been pasted yet while waiting to paste, so there's no cursor to lose.
            guard let self, self.model.review != nil, self.pendingPaste == nil,
                  event.cgEvent?.getIntegerValueField(.eventSourceUserData) != PasteDelivery.syntheticEventTag
            else { return }
            self.clearReview()
        }) {
            mouseMonitors.append(other)
        }
    }

    // MARK: Replacement picker

    /// Shows, hides or resizes the picker to match the model, just above the capsule.
    private func updatePicker() {
        guard model.isPickerOpen, model.review != nil else {
            pickerPanel.orderOut(nil)
            return
        }
        let host = PickerHostingView(rootView: ReplacementPickerView(
            model: model,
            choose: { [weak self] occurrence, revert in self?.choose(occurrence, revert: revert) },
            finish: { [weak self] paste in self?.finishPendingPaste(paste: paste) }
        ))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        pickerPanel.contentView = host
        let capsuleTop = panel.frame.minY + Self.capsuleBottomPadding + model.capsuleSize.height
        var origin = NSPoint(x: panel.frame.midX - size.width / 2, y: capsuleTop + 6)
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(origin.y, visible.maxY - size.height)
        }
        pickerPanel.setFrame(NSRect(origin: origin, size: size), display: true)
        pickerPanel.orderFrontRegardless()
    }

    private func choose(_ occurrence: Int, revert: Bool) {
        guard let old = model.currentText, model.reverted.contains(occurrence) != revert else { return }
        model.setReverted(occurrence, revert)
        guard !model.isBeforePaste else { return }
        guard let new = model.currentText, rewritePaste?(old, new) == true else {
            clearReview()
            return
        }
    }

    private func updateClickThrough() {
        let overCapsule = capsuleScreenRect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == overCapsule {
            panel.ignoresMouseEvents = !overCapsule
        }
    }

    @objc private func panelDidMove() {
        if pickerPanel.isVisible { updatePicker() }
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
                if let review = model.review {
                    Text("\(review.occurrences.count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .transition(.opacity)
                }
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
        .frame(width: model.capsuleSize.width, height: model.capsuleSize.height)
        .background(Capsule().fill(.black.opacity(0.72)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        .animation(.spring(duration: 0.35, bounce: 0.25), value: model.capsuleSize)
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

/// Lets the picker's buttons respond to the first click, since its panel never becomes key.
private final class PickerHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// One group per replaced occurrence, shown in a few words of context: the dictionary's
/// written form or what was actually said. White on black, like the capsule.
private struct ReplacementPickerView: View {
    let model: FloatingIndicatorModel
    let choose: (_ occurrence: Int, _ revert: Bool) -> Void
    /// Before pasting: Paste (true) or Cancel (false).
    let finish: (_ paste: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let review = model.review {
                ForEach(review.occurrences.indices, id: \.self) { index in
                    let occurrence = review.occurrences[index]
                    let reverted = model.reverted.contains(index)
                    let context = review.context(of: index)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(context.before)\(Text(reverted ? occurrence.original : occurrence.written).bold().foregroundStyle(.white))\(context.after)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2)
                            .frame(maxWidth: 260, alignment: .leading)
                        option(occurrence.written, selected: !reverted) { choose(index, false) }
                        option(occurrence.original, note: "original", selected: reverted) { choose(index, true) }
                    }
                }
            }
            if model.isBeforePaste {
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") { finish(false) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.6))
                    Button { finish(true) } label: {
                        Text("Paste")
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.white))
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 12, weight: .medium))
            }
        }
        .padding(12)
        .frame(minWidth: 160, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.4), lineWidth: 1))
        .fixedSize()
    }

    private func option(_ word: String, note: String? = nil, selected: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 11))
                Text(word)
                if let note {
                    Text("(\(note))").foregroundStyle(.white.opacity(0.6))
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
