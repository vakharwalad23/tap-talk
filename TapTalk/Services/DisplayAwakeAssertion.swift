import Foundation
import IOKit.pwr_mgt

/// Keeps the display from sleeping on idle while held: a toggle recording has no key held down,
/// so a long dictation would otherwise end in a dimmed, locking screen. Both calls are idempotent.
final class DisplayAwakeAssertion {
    private var assertionID: IOPMAssertionID?

    func hold() {
        guard assertionID == nil else { return }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "TapTalk hands-free dictation" as CFString,
            &id
        )
        if result == kIOReturnSuccess { assertionID = id }
    }

    func release() {
        guard let id = assertionID else { return }
        IOPMAssertionRelease(id)
        assertionID = nil
    }

    deinit { release() }
}
