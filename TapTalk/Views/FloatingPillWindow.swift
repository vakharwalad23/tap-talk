import AppKit
import SwiftUI
import TapTalkLearning

final class FloatingPillController {
    static let shared = FloatingPillController()

    private var window: NSPanel?
    private var hostingView: PillHostingView?
    private let holder = PillStateHolder()

    private var autoHideWork: DispatchWorkItem?

    private init() {}

    func show(state: PillState) {
        autoHideWork?.cancel()
        autoHideWork = nil

        if window == nil { createWindow() }

        apply(state)
        window?.orderFrontRegardless()

        let visibleFor: Double
        switch state {
        case .done: visibleFor = 1.5
        case .notice: visibleFor = 4.0  // long enough to reach Undo
        default: return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.autoHideWork = nil
            self?.apply(.idle)
        }
        autoHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + visibleFor, execute: work)
    }

    // A notice is sized to its text; every other state fits the small panel, which keeps the
    // click-catching area at the bottom of the screen as small as it was.
    private static func panelSize(for state: PillState) -> NSSize {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        func measure(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        let content: CGFloat
        switch state {
        case .notice(let event): content = measure(PillView.noticeText(event)) + measure("Undo")
        case .notPasted:         content = measure(PillView.notPastedText)
        default:                 return NSSize(width: smallWidth, height: panelHeight)
        }
        let width = ceil(content + noticeChrome)
        return NSSize(width: min(max(width, smallWidth), maxNoticeWidth), height: panelHeight)
    }

    private static let smallWidth: CGFloat = 186
    private static let panelHeight: CGFloat = 56
    // Checkmark 14, two 8 pt gaps, the capsule padding per side, 12 pt per side for the shadow, and
    // 4 pt for the gap between NSString measurement and SwiftUI rendering.
    private static let noticeChrome: CGFloat = 14 + 16 + 2 * PillView.textPadding + 24 + 4
    // Past this a notice truncates rather than spanning the screen.
    private static let maxNoticeWidth: CGFloat = 640

    // The small pill's frame before a notice widened it, and the frame that notice got.
    private var restingFrame: NSRect?
    private var widenedFrame: NSRect?

    private func apply(_ state: PillState) {
        #if DEBUG
        let state = Self.previewState ?? state
        #endif
        let size = Self.panelSize(for: state)
        if let panel = window, panel.frame.size != size {
            let frame: NSRect
            if let resting = restingFrame, panel.frame == widenedFrame, resting.size == size {
                // Back to where the user left the pill, even if the notice had to shift to fit the screen.
                frame = resting
            } else {
                frame = Self.resized(panel.frame, to: size, within: (panel.screen ?? NSScreen.main)?.visibleFrame)
            }
            if size.width != Self.smallWidth {
                if restingFrame == nil { restingFrame = panel.frame }
                widenedFrame = frame
            } else {
                restingFrame = nil
                widenedFrame = nil
            }
            panel.setFrame(frame, display: false)
            hostingView?.frame = NSRect(origin: .zero, size: size)
        }
        if state == .recording, holder.state != .recording { holder.recordingStart = Date() }
        holder.state = state
    }

    // Resizes around the current center and bottom, so a dragged pill stays put, but never past the
    // visible screen edge, where a wide notice would lose its "to" side and Undo.
    private static func resized(_ current: NSRect, to size: NSSize, within visible: NSRect?) -> NSRect {
        var x = current.midX - size.width / 2
        if let visible { x = min(max(x, visible.minX), visible.maxX - size.width) }
        return NSRect(x: x, y: current.minY, width: size.width, height: size.height)
    }

    // Live mic RMS for the recording waveform. Cheap - read by the pill's render timer.
    func setLevel(_ rms: Float) {
        holder.level = rms
    }

    // ponytail: the whole panel, transparent margin included, counts as the pill; a click there is
    // never a shortcut. AppKit coordinates.
    func contains(screenPoint point: CGPoint) -> Bool {
        guard let window, window.isVisible else { return false }
        return window.frame.contains(point)
    }

    // Returns to idle - pill stays visible
    func hide() {
        autoHideWork?.cancel()
        autoHideWork = nil

        if window == nil { createWindow() }
        apply(.idle)
        window?.orderFrontRegardless()
    }

    private func createWindow() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let hv = PillHostingView(rootView: PillView(holder: holder))
        hv.wantsLayer = true
        hv.layer?.backgroundColor = NSColor.clear.cgColor

        let size = NSSize(width: Self.smallWidth, height: Self.panelHeight)
        hv.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hv
        hostingView = hv

        DispatchQueue.main.async {
            hv.layer?.backgroundColor = NSColor.clear.cgColor
        }

        positionWindow(panel, size: size)
        #if DEBUG
        Self.applyPreviewAppearance(to: panel)
        #endif
        window = panel
    }

    #if DEBUG
    // Holds one state for screenshots: open TapTalk.app --args -TapTalkPillPreview notice
    // -TapTalkPillAppearance NSAppearanceNameDarkAqua
    private static let previewState: PillState? = {
        switch UserDefaults.standard.string(forKey: "TapTalkPillPreview") {
        case "recording":    return .recording
        case "transcribing": return .transcribing
        case "rewriting":    return .rewriting
        case "done":         return .done
        case "notice":       return .notice(.learned(LearnedRule(from: "tap talk", to: "TapTalk")))
        case "notPasted":    return .notPasted
        default:             return nil
        }
    }()

    private static func applyPreviewAppearance(to panel: NSPanel) {
        guard let name = UserDefaults.standard.string(forKey: "TapTalkPillAppearance") else { return }
        panel.appearance = NSAppearance(named: NSAppearance.Name(rawValue: name))
    }
    #endif

    private func positionWindow(_ panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let x = screen.frame.minX + (screen.frame.width - size.width) / 2
        let y = screen.visibleFrame.minY + 56
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }
}

// The panel never becomes key; without first-mouse the tick or cross would need a focusing click.
final class PillHostingView: NSHostingView<PillView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
