import SwiftUI

struct LanguagePicker: View {
    @Binding var selectedLanguage: String?

    private let languages: [(id: String?, label: String)] = [
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
