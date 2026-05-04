import AppKit
import SwiftUI

final class FloatingPillController {
    static let shared = FloatingPillController()

    private var window: NSPanel?
    private var hostingView: NSHostingView<PillView>?
    private let holder = PillStateHolder()

    // Both tracked so show() can cancel a pending orderOut
    private var autoHideWork: DispatchWorkItem?
    private var orderOutWork: DispatchWorkItem?

    private init() {}

    func show(state: PillState) {
        autoHideWork?.cancel()
        autoHideWork = nil
        // Cancel pending orderOut — prevents it firing after we've shown the pill again
        orderOutWork?.cancel()
        orderOutWork = nil

        if window == nil { createWindow() }

        holder.state = state
        window?.orderFrontRegardless()

        if state == .done {
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            autoHideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
    }

    func hide() {
        autoHideWork?.cancel()
        autoHideWork = nil
        orderOutWork?.cancel()
        orderOutWork = nil

        holder.state = .hidden

        // Wait for hide animation before removing window
        let work = DispatchWorkItem { [weak self] in self?.window?.orderOut(nil) }
        orderOutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
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

        // Single PillView instance — holder mutations drive state changes reactively
        let hv = NSHostingView(rootView: PillView(holder: holder))
        hv.wantsLayer = true
        hv.layer?.backgroundColor = NSColor.clear.cgColor

        let size = NSSize(width: 186, height: 56)
        hv.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hv
        hostingView = hv

        // Clear layer background again after contentView assignment (layer may be recreated)
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
