import CoreGraphics
import XCTest
@testable import AwakeCup

final class MenuBarItemRecordTests: XCTestCase {
    func testRecordUsesTitleWhenAvailable() {
        let snapshot = MenuBarItemSnapshot(
            bundleIdentifier: "com.example.clock",
            processID: 42,
            title: "Clock",
            description: "Menu Bar Clock",
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 100, y: 0, width: 24, height: 24),
            actionNames: ["AXPress"]
        )

        let record = MenuBarItemRecord(snapshot: snapshot)

        XCTAssertEqual(record.displayName, "Clock")
        XCTAssertEqual(record.manageability, .manageable)
    }

    func testRecordFallsBackToDescriptionWhenTitleMissing() {
        let snapshot = MenuBarItemSnapshot(
            bundleIdentifier: "com.example.vpn",
            processID: 77,
            title: nil,
            description: "VPN",
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 150, y: 0, width: 18, height: 24),
            actionNames: ["AXPress"]
        )

        let record = MenuBarItemRecord(snapshot: snapshot)

        XCTAssertEqual(record.displayName, "VPN")
    }

    func testRecordFallsBackToDescriptionWhenTitleIsEmpty() {
        let snapshot = MenuBarItemSnapshot(
            bundleIdentifier: "com.example.vpn",
            processID: 77,
            title: "",
            description: "VPN",
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 150, y: 0, width: 18, height: 24),
            actionNames: ["AXPress"]
        )

        let record = MenuBarItemRecord(snapshot: snapshot)

        XCTAssertEqual(record.displayName, "VPN")
    }

    func testRecordFallsBackToBundleIdentifierWhenTitleAndDescriptionAreEmpty() {
        let snapshot = MenuBarItemSnapshot(
            bundleIdentifier: "com.example.fallback",
            processID: 88,
            title: "",
            description: "",
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 160, y: 0, width: 18, height: 24),
            actionNames: ["AXPress"]
        )

        let record = MenuBarItemRecord(snapshot: snapshot)

        XCTAssertEqual(record.displayName, "com.example.fallback")
    }

    func testRecordMarksMissingPressActionAsUnmanaged() {
        let snapshot = MenuBarItemSnapshot(
            bundleIdentifier: "com.example.readonly",
            processID: 11,
            title: "ReadOnly",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 180, y: 0, width: 20, height: 24),
            actionNames: []
        )

        let record = MenuBarItemRecord(snapshot: snapshot)

        XCTAssertEqual(record.manageability, .unmanaged(reason: "Missing AXPress action"))
    }

    func testRecordIsStillManageableWhenFrameIsMissingButPressActionExists() {
        let snapshot = MenuBarItemSnapshot(
            bundleIdentifier: "com.example.framefree",
            processID: 12,
            title: "FrameFree",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: nil,
            actionNames: ["AXPress"]
        )

        let record = MenuBarItemRecord(snapshot: snapshot)

        XCTAssertEqual(record.manageability, .manageable)
    }

    func testStableIDChangesWhenBundleChanges() {
        let left = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.first",
            processID: 1,
            title: "Clock",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 100, y: 0, width: 24, height: 24),
            actionNames: ["AXPress"]
        ))

        let right = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.second",
            processID: 1,
            title: "Clock",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 100, y: 0, width: 24, height: 24),
            actionNames: ["AXPress"]
        ))

        XCTAssertNotEqual(left.id, right.id)
    }
}
