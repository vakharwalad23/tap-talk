import SwiftUI

struct LanguagePicker: View {
    @Binding var selectedLanguage: String?

    // Supplied by the active engine so the menu never offers a language the model cannot
    // produce. Codes must be the exact keys the engine's model recognizes.
    let languages: [(id: String?, label: String)]

    // OpenAI's cloud model covers far more than any on-device engine, so it keeps the
    // broad list. On-device engines supply their own verified subset.
    static let cloudLanguages: [(id: String?, label: String)] = [
        (nil, "Auto-detect"),
        ("en", "English"),
        ("hi", "Hindi"),
        ("ta", "Tamil"),
        ("te", "Telugu"),
        ("mr", "Marathi"),
        ("bn", "Bengali"),
        ("gu", "Gujarati"),
        ("kn", "Kannada"),
        ("ml", "Malayalam"),
        ("pa", "Punjabi"),
        ("ur", "Urdu"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("ja", "Japanese"),
        ("zh", "Chinese"),
    ]

    var body: some View {
        Picker("Language", selection: $selectedLanguage) {
            ForEach(languages, id: \.id) { lang in
                Text(lang.label).tag(lang.id)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 140)
    }
}
