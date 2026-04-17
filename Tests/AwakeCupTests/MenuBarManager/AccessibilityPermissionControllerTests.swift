import XCTest
@testable import AwakeCup

@MainActor
final class AccessibilityPermissionControllerTests: XCTestCase {
    func testInitialStateIsDeniedAndNotManageableWhenCheckerReturnsFalse() {
        let checker = StubAccessibilityTrustChecker(responses: [false])

        let controller = AccessibilityPermissionController(checker: checker)

        XCTAssertEqual(controller.state, .denied)
        XCTAssertFalse(controller.canManageItems)
        XCTAssertEqual(checker.promptCalls, 0)
    }

    func testInitialStateIsGrantedAndManageableWhenCheckerReturnsTrue() {
        let checker = StubAccessibilityTrustChecker(responses: [true])

        let controller = AccessibilityPermissionController(checker: checker)

        XCTAssertEqual(controller.state, .granted)
        XCTAssertTrue(controller.canManageItems)
        XCTAssertEqual(checker.promptCalls, 0)
    }

    func testRefreshUpdatesStateAfterInitialization() {
        let checker = StubAccessibilityTrustChecker(responses: [false, true])
        let controller = AccessibilityPermissionController(checker: checker)

        XCTAssertEqual(controller.state, .denied)
        XCTAssertFalse(controller.canManageItems)

        controller.refresh()

        XCTAssertEqual(controller.state, .granted)
        XCTAssertTrue(controller.canManageItems)
    }

    func testRequestAccessPromptsAndLeavesDeniedWhenStillUntrusted() {
        let checker = StubAccessibilityTrustChecker(responses: [false, false])
        let controller = AccessibilityPermissionController(checker: checker)

        XCTAssertEqual(controller.state, .denied)
        XCTAssertFalse(controller.canManageItems)
        XCTAssertEqual(checker.promptCalls, 0)

        controller.requestAccess()

        XCTAssertEqual(controller.state, .denied)
        XCTAssertFalse(controller.canManageItems)
        XCTAssertEqual(checker.promptCalls, 1)
    }
}

private final class StubAccessibilityTrustChecker: AccessibilityTrustChecking {
    private var responses: [Bool]
    private(set) var promptCalls: Int = 0

    init(responses: [Bool]) {
        self.responses = responses
    }

    func isTrusted(prompt: Bool) -> Bool {
        if prompt { promptCalls += 1 }
        if responses.isEmpty { return false }
        return responses.removeFirst()
    }
}
