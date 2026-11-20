import SwiftUI

/// The small rounded button used on cards and banners; prominent is the filled primary action.
struct CardButton: View {
    let title: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: prominent ? .semibold : .medium))
            .foregroundStyle(prominent ? Color.white : AppTheme.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(prominent ? AppTheme.accent : AppTheme.divider)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
