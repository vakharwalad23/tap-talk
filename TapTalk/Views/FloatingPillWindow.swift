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

        holder.state = state
        window?.orderFrontRegardless()

        if state == .done {
            let work = DispatchWorkItem { [weak self] in
                self?.autoHideWork = nil
                self?.holder.state = .idle
            }
            autoHideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
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
        holder.state = .idle
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
