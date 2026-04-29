import AppKit
import XCTest
@testable import AwakeCup

final class TopMenuBarAutoHideTests: XCTestCase {
    func testEnablingAutoHideMenuBarPreservesUnrelatedOptions() {
        let updatedOptions = TopMenuBarAutoHide.options(
            from: [.autoHideDock],
            enabled: true
        )

        XCTAssertTrue(updatedOptions.contains(.autoHideMenuBar))
        XCTAssertTrue(updatedOptions.contains(.autoHideDock))
    }

    func testEnablingAutoHideMenuBarRemovesHardHideMenuBar() {
        let updatedOptions = TopMenuBarAutoHide.options(
            from: [.hideMenuBar],
            enabled: true
        )

        XCTAssertTrue(updatedOptions.contains(.autoHideMenuBar))
        XCTAssertFalse(updatedOptions.contains(.hideMenuBar))
    }

    func testDisablingAutoHideMenuBarLeavesUnrelatedOptions() {
        let updatedOptions = TopMenuBarAutoHide.options(
            from: [.autoHideMenuBar, .autoHideDock],
            enabled: false
        )

        XCTAssertFalse(updatedOptions.contains(.autoHideMenuBar))
        XCTAssertTrue(updatedOptions.contains(.autoHideDock))
    }
}
