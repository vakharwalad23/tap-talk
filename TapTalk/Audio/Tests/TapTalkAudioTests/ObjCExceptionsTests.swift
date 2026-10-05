import Foundation
import ObjCExceptions
import XCTest

final class ObjCExceptionsTests: XCTestCase {
    func testRaisedExceptionIsReturnedInsteadOfAborting() {
        let caught = tt_catch_exception {
            NSException(name: .invalidArgumentException, reason: "format mismatch", userInfo: nil).raise()
        }
        XCTAssertEqual(caught?.name, .invalidArgumentException)
        XCTAssertEqual(caught?.reason, "format mismatch")
    }

    func testBlockThatDoesNotRaiseReturnsNilAndRuns() {
        var ran = false
        XCTAssertNil(tt_catch_exception { ran = true })
        XCTAssertTrue(ran)
    }
}
