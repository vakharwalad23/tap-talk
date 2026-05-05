import SwiftUI
import Carbon.HIToolbox

enum AppTheme {
    // Backgrounds
    static let windowBg  = Color(hex: "f4f3f1")
    static let sidebarBg = Color(hex: "eceae6")
    static let sectionBg = Color(hex: "eceae6")
    static let divider   = Color(hex: "dddad5")

    // Text
    static let primary   = Color(hex: "1a1917")
    static let secondary = Color(hex: "1a1917").opacity(0.6)
    static let tertiary  = Color(hex: "1a1917").opacity(0.4)

    // Accent / states
    static let accent    = Color(hex: "1a1917")
    static let danger    = Color(red: 1,   green: 0.23, blue: 0.19)
    static let success   = Color(red: 0.2, green: 0.78, blue: 0.35)

    static func keyLabel(for code: UInt16) -> String {
        switch Int(code) {
        case kVK_RightCommand: return "Right ⌘"
        case kVK_RightOption:  return "Right ⌥"
        case kVK_RightControl: return "Right ⌃"
        case kVK_RightShift:   return "Right ⇧"
        case kVK_Command:      return "Left ⌘"
        case kVK_Option:       return "Left ⌥"
        case kVK_Control:      return "Left ⌃"
        case kVK_Shift:        return "Left ⇧"
        default:               return "Key \(code)"
        }
    }
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double( int        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
