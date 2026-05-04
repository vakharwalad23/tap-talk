import SwiftUI

struct ModelTierPicker: View {
    @Binding var selectedTier: UInt8
    let installedTiers: [UInt8]

    private let allTiers = availableTiers()

    var body: some View {
        Picker("Model", selection: $selectedTier) {
            ForEach(allTiers.filter { installedTiers.contains($0.id) }, id: \.id) { tier in
                Text(tier.name).tag(tier.id)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 160)
    }
}
