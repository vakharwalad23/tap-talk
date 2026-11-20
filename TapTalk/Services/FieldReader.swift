import ApplicationServices
import Carbon.HIToolbox

/// The outcome of reading a remembered text field.
enum FieldRead {
    case text(String)
    case gone
    case timedOut
    case tooLong
    case unreadable
}

/// Accessibility reads of the focused text field, used to learn from corrections. Every call is a
/// message to another app, so call these off the main actor; each message gives up after
/// `messagingTimeout` so a hung app cannot stall TapTalk.
enum FieldReader {
    static let messagingTimeout: Float = 0.25
    /// Longer fields (whole documents) are skipped rather than read.
    static let maxCharacters = 20_000

    /// The focused element when it is a readable, non-secure text field.
    static func focusedTextField() -> AXUIElement? {
        guard !IsSecureEventInputEnabled() else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let candidate = focused,
              CFGetTypeID(candidate) == AXUIElementGetTypeID()
        else { return nil }
        // SAFETY: the type ID was checked on the line above.
        let field = candidate as! AXUIElement
        AXUIElementSetMessagingTimeout(field, messagingTimeout)

        // Role, subrole and character count in one message; no count means not a text field.
        let names = [kAXRoleAttribute, kAXSubroleAttribute, kAXNumberOfCharactersAttribute] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(field, names, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
              let list = values as? [AnyObject], list.count == 3
        else { return nil }
        let secure = kAXSecureTextFieldSubrole as String
        if (list[0] as? String) == secure || (list[1] as? String) == secure { return nil }
        guard list[2] is NSNumber else { return nil }
        return field
    }

    /// The field's text, read once. Fields over `maxCharacters` are not read.
    static func text(of field: AXUIElement) -> FieldRead {
        guard !IsSecureEventInputEnabled() else { return .unreadable }
        var count: AnyObject?
        switch AXUIElementCopyAttributeValue(field, kAXNumberOfCharactersAttribute as CFString, &count) {
        case .success: break
        case .invalidUIElement: return .gone
        case .cannotComplete: return .timedOut
        default: return .unreadable
        }
        guard let characters = count as? Int else { return .unreadable }
        guard characters <= maxCharacters else { return .tooLong }
        var value: AnyObject?
        switch AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &value) {
        case .success: return (value as? String).map(FieldRead.text) ?? .unreadable
        case .invalidUIElement: return .gone
        case .cannotComplete: return .timedOut
        default: return .unreadable
        }
    }
}
