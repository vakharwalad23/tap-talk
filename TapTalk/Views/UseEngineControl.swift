import SwiftUI

/// "In use" on the active speech engine's card, otherwise a "Use" button that makes it active.
struct UseEngineControl: View {
    let isInUse: Bool
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        if isInUse {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                Text("In use")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(AppTheme.success)
        } else {
            CardButton(title: "Use", prominent: false, action: action)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.5)
        }
    }
}
