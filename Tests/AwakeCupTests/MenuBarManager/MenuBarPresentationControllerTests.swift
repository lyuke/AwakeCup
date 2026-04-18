import Foundation
import XCTest
@testable import AwakeCup

@MainActor
final class MenuBarPresentationControllerTests: XCTestCase {
    func testShowPreferredUsesExpandedStripWhenAvailable() {
        let controller = MenuBarPresentationController()
        controller.configuration = MenuBarPresentationConfiguration(
            preferredRevealMode: .expandedStrip,
            autoCollapseAfter: 5
        )
        let now = Date(timeIntervalSince1970: 10)

        controller.showPreferred(canPresentExpandedStrip: true, now: now)

        XCTAssertEqual(controller.state.activeSurface, .expandedStrip)
        XCTAssertEqual(controller.state.autoCollapseDeadline, now.addingTimeInterval(5))
    }

    func testShowPreferredFallsBackToPanelWhenExpandedStripUnavailable() {
        let controller = MenuBarPresentationController()
        controller.configuration = MenuBarPresentationConfiguration(
            preferredRevealMode: .expandedStrip,
            autoCollapseAfter: 5
        )
        let now = Date(timeIntervalSince1970: 10)

        controller.showPreferred(canPresentExpandedStrip: false, now: now)

        XCTAssertEqual(controller.state.activeSurface, .panel)
        XCTAssertNil(controller.state.autoCollapseDeadline)
    }

    func testShowPreferredUsesPanelWhenPanelIsPreferred() {
        let controller = MenuBarPresentationController()
        controller.configuration = MenuBarPresentationConfiguration(
            preferredRevealMode: .panel,
            autoCollapseAfter: 5
        )
        let now = Date(timeIntervalSince1970: 10)

        controller.showPreferred(canPresentExpandedStrip: true, now: now)

        XCTAssertEqual(controller.state.activeSurface, .panel)
        XCTAssertNil(controller.state.autoCollapseDeadline)
    }

    func testDismissClearsActiveSurfaceAndDeadline() {
        let controller = MenuBarPresentationController()
        controller.configuration = MenuBarPresentationConfiguration(
            preferredRevealMode: .expandedStrip,
            autoCollapseAfter: 5
        )
        let now = Date(timeIntervalSince1970: 10)

        controller.showPreferred(canPresentExpandedStrip: true, now: now)
        controller.dismiss()

        XCTAssertNil(controller.state.activeSurface)
        XCTAssertNil(controller.state.autoCollapseDeadline)
    }

    func testTickDismissesExpandedStripAfterDeadline() {
        let controller = MenuBarPresentationController()
        controller.configuration = MenuBarPresentationConfiguration(
            preferredRevealMode: .expandedStrip,
            autoCollapseAfter: 5
        )
        let now = Date(timeIntervalSince1970: 10)

        controller.showPreferred(canPresentExpandedStrip: true, now: now)
        controller.tick(now: now.addingTimeInterval(4))

        XCTAssertEqual(controller.state.activeSurface, .expandedStrip)
        XCTAssertEqual(controller.state.autoCollapseDeadline, now.addingTimeInterval(5))

        controller.tick(now: now.addingTimeInterval(5))

        XCTAssertNil(controller.state.activeSurface)
        XCTAssertNil(controller.state.autoCollapseDeadline)
    }
}
