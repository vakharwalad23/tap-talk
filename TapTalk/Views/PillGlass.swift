import AppKit
import SwiftUI

/// Frosted capsule behind every pill state: behind-window blur that follows the system appearance,
/// a hairline border and a soft shadow outside the capsule only, so the glass itself stays clear.
struct PillGlass: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        CapsuleBlur()
            .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
            .background(CapsuleShadow())
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }
}

private struct CapsuleBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> CapsuleEffectView {
        let view = CapsuleEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        // The panel is never key, so a view that follows the window state would render inactive.
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: CapsuleEffectView, context: Context) {}
}

// maskImage is the supported way to shape a behind-window blur; a layer corner radius is not.
private final class CapsuleEffectView: NSVisualEffectView {
    private var maskHeight: CGFloat = 0

    override func layout() {
        super.layout()
        let height = bounds.height
        guard height > 0, height != maskHeight else { return }
        maskHeight = height
        let radius = height / 2
        let image = NSImage(size: NSSize(width: height + 1, height: height), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        maskImage = image
    }
}

// A shadow cut out where the capsule sits; a plain shadow needs an opaque shape, which would cloud the glass.
private struct CapsuleShadow: View {
    var body: some View {
        Capsule()
            .fill(Color.black)
            .shadow(color: Color.black.opacity(0.22), radius: 6, x: 0, y: 2)
            .mask(
                Rectangle()
                    .padding(-16)
                    .overlay(Capsule().blendMode(.destinationOut))
                    .compositingGroup()
            )
    }
}
