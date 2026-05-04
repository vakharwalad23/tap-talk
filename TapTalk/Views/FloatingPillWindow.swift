import AppKit
import SwiftUI

final class FloatingPillController {
    static let shared = FloatingPillController()

    private var window: NSPanel?
    private var hostingView: NSHostingView<PillView>?
    private var hideTask: DispatchWorkItem?

    private init() {}

    func show(state: PillState) {
        hideTask?.cancel()
        hideTask = nil

        if window == nil { createWindow() }

        updateContent(state)
        window?.orderFrontRegardless()

        if state == .done {
            let task = DispatchWorkItem { [weak self] in self?.hide() }
            hideTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: task)
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        updateContent(.hidden)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.window?.orderOut(nil)
        }
    }

    private func updateContent(_ state: PillState) {
        hostingView?.rootView = PillView(pillState: state)
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
        panel.ignoresMouseEvents = false          // allow dragging
        panel.isMovableByWindowBackground = true  // drag anywhere on pill
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let pillView = PillView(pillState: .hidden)
        let hv = NSHostingView(rootView: pillView)
        hv.wantsLayer = true
        hv.layer?.backgroundColor = NSColor.clear.cgColor

        let size = NSSize(width: 186, height: 56)
        hv.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hv
        hostingView = hv

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
