import XCTest
@testable import AwakeCup

final class MenuBarAXClientTests: XCTestCase {
    func testObservationRegistrationRequiresAtLeastOneSuccessfulNotification() {
        XCTAssertFalse(
            MenuBarAXObservationRegistrationPolicy.shouldTrackObserver(
                notificationResults: [.notificationUnsupported, .notificationUnsupported, .failure]
            )
        )
    }

    func testObservationRegistrationTracksObserverWhenAnyNotificationSucceeds() {
        XCTAssertTrue(
            MenuBarAXObservationRegistrationPolicy.shouldTrackObserver(
                notificationResults: [.notificationUnsupported, .success, .failure]
            )
        )
    }

    func testIdentityHintPrefersAXIdentifier() {
        let hint = MenuBarAXClient.identityHint(
            identifier: "status-wifi",
            help: "Wi-Fi",
            siblingIndex: 2
        )

        XCTAssertEqual(hint, "identifier:status-wifi")
    }

    func testIdentityHintFallsBackToAXHelpWhenIdentifierMissing() {
        let hint = MenuBarAXClient.identityHint(
            identifier: "   ",
            help: "Battery",
            siblingIndex: 1
        )

        XCTAssertEqual(hint, "help:Battery")
    }

    func testIdentityHintFallsBackToSiblingIndexWhenNoStableAttributesExist() {
        let hint = MenuBarAXClient.identityHint(
            identifier: nil,
            help: nil,
            siblingIndex: 3
        )

        XCTAssertEqual(hint, "index:3")
    }
}
