import AppKit
import SwiftUI

final class FloatingPillController {
    static let shared = FloatingPillController()

    private var window: NSPanel?
    private var hostingView: NSHostingView<PillView>?
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

    // A notice needs room for its text; every other state fits the small panel, which keeps the
    // click-catching area at the bottom of the screen as small as it was.
    private static func panelSize(for state: PillState) -> NSSize {
        if case .notice = state { return NSSize(width: 420, height: 56) }
        return NSSize(width: 186, height: 56)
    }

    private func apply(_ state: PillState) {
        let size = Self.panelSize(for: state)
        if let panel = window, panel.frame.size != size {
            positionWindow(panel, size: size)
            hostingView?.frame = NSRect(origin: .zero, size: size)
        }
        holder.state = state
    }

    // Live mic RMS for the recording waveform. Cheap - read by the pill's render timer.
    func setLevel(_ rms: Float) {
        holder.level = rms
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

        let hv = NSHostingView(rootView: PillView(holder: holder))
        hv.wantsLayer = true
        hv.layer?.backgroundColor = NSColor.clear.cgColor

        let size = NSSize(width: 186, height: 56)
        hv.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hv
        hostingView = hv

        DispatchQueue.main.async {
            hv.layer?.backgroundColor = NSColor.clear.cgColor
        }

        positionWindow(panel, size: size)
        window = panel
    }

    private func positionWindow(_ panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let x = (screen.frame.width - size.width) / 2
        let y = screen.visibleFrame.minY + 56
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }
}
