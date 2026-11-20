import SwiftUI

/// Every model in one place: download it, choose it, set its options, remove it.
struct ModelsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Models")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.primary)
                    Text("Speech and Smart Mode. Runs on this Mac unless you choose Cloud or a Smart Mode server")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.tertiary)
                }
                .padding(.bottom, 12)

                groupLabel("Speech")
                OrukeetCard()
                ParakeetCard()
                NemotronCard()
                CloudCard()
            }
            .padding(24)
        }
        .background(AppTheme.windowBg)
    }

    private func groupLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.secondary)
            .padding(.top, 4)
    }
}
