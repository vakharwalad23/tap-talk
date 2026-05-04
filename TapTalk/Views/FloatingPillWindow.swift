import AppKit
import SwiftUI

final class FloatingPillController {
    static let shared = FloatingPillController()

    private var window: NSPanel?
    private var hostingView: NSHostingView<PillView>?
    private var hideTask: DispatchWorkItem?
    private var currentState: PillState = .hidden

    private init() {}

    func show(state: PillState) {
        hideTask?.cancel()
        hideTask = nil

        if window == nil {
            createWindow()
        }

        setContentState(state)
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
        setContentState(.hidden)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.window?.orderOut(nil)
        }
    }

    private func setContentState(_ state: PillState) {
        currentState = state
        if let hv = hostingView {
            hv.rootView = PillView(pillState: state)
        }
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
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let pillView = PillView(pillState: .hidden)
        let hv = NSHostingView(rootView: pillView)
        hv.frame = NSRect(x: 0, y: 0, width: 220, height: 72)
        panel.contentView = hv
        hostingView = hv

        positionWindow(panel)
        window = panel
    }

    private func positionWindow(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let sw = screen.frame.width
        let sh = screen.frame.height
        let visibleBottom = screen.visibleFrame.minY
        let pw: CGFloat = 220
        let ph: CGFloat = 72
        let x = (sw - pw) / 2
        let y = visibleBottom + 60
        panel.setFrame(NSRect(x: x, y: y, width: pw, height: ph), display: false)
    }
}
