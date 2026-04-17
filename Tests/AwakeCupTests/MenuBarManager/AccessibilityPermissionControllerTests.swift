import XCTest
@testable import AwakeCup

@MainActor
final class AccessibilityPermissionControllerTests: XCTestCase {
    func testRefreshSetsGrantedWhenCheckerReturnsTrue() {
        let checker = StubAccessibilityTrustChecker(responses: [false, true])
        let controller = AccessibilityPermissionController(checker: checker)

        controller.refresh()
        XCTAssertEqual(controller.state, .denied)

        controller.refresh()
        XCTAssertEqual(controller.state, .granted)
    }

    func testRequestAccessPromptsAndLeavesDeniedWhenStillUntrusted() {
        let checker = StubAccessibilityTrustChecker(responses: [false])
        let controller = AccessibilityPermissionController(checker: checker)

        controller.requestAccess()

        XCTAssertEqual(controller.state, .denied)
        XCTAssertEqual(checker.promptCalls, 1)
    }
}
