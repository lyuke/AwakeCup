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

    func testRecordFallsBackToDescriptionWhenTitleIsWhitespaceOnly() {
        let snapshot = MenuBarItemSnapshot(
            bundleIdentifier: "com.example.vpn",
            processID: 77,
            title: "   ",
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

    func testPersistentIDChangesWhenBundleChanges() {
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

        XCTAssertNotEqual(left.persistentID, right.persistentID)
    }

    func testPersistentIDIgnoresTitleAndDescriptionChanges() {
        let left = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.stable",
            processID: 1,
            title: "Clock",
            description: "Menu Bar Clock",
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 100, y: 0, width: 24, height: 24),
            actionNames: ["AXPress"]
        ))

        let right = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.stable",
            processID: 1,
            title: "Timer",
            description: "Timer Menu Bar Item",
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 100, y: 0, width: 24, height: 24),
            actionNames: ["AXPress"]
        ))

        XCTAssertEqual(left.persistentID, right.persistentID)
    }

    func testPersistentIDIgnoresActionNameOrdering() {
        let left = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.ordering",
            processID: 1,
            title: "Clock",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 100, y: 0, width: 24, height: 24),
            actionNames: ["AXShowMenu", "AXPress"]
        ))

        let right = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.ordering",
            processID: 1,
            title: "Clock",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 100, y: 0, width: 24, height: 24),
            actionNames: ["AXPress", "AXShowMenu"]
        ))

        XCTAssertEqual(left.persistentID, right.persistentID)
    }

    func testPersistentIDIgnoresActionSetChanges() {
        let left = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.actions",
            processID: 1,
            title: "Clock",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 100, y: 0, width: 24, height: 24),
            actionNames: ["AXPress", "AXShowMenu"]
        ))

        let right = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.actions",
            processID: 1,
            title: "Clock",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 100, y: 0, width: 24, height: 24),
            actionNames: ["AXPress"]
        ))

        XCTAssertEqual(left.persistentID, right.persistentID)
    }

    func testPersistentIDIgnoresFrameChanges() {
        let left = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.geometry",
            processID: 1,
            title: "Clock",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 100, y: 0, width: 24, height: 24),
            actionNames: ["AXPress"]
        ))

        let right = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.geometry",
            processID: 1,
            title: "Clock",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 220, y: 0, width: 24, height: 24),
            actionNames: ["AXPress"]
        ))

        XCTAssertEqual(left.persistentID, right.persistentID)
    }

    func testRuntimeIDChangesWhenFrameChanges() {
        let left = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.runtime",
            processID: 1,
            title: "Clock",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 100, y: 0, width: 24, height: 24),
            actionNames: ["AXPress"]
        ))

        let right = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.runtime",
            processID: 1,
            title: "Clock",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 220, y: 0, width: 24, height: 24),
            actionNames: ["AXPress"]
        ))

        XCTAssertNotEqual(left.runtimeID, right.runtimeID)
    }

    func testWhitespaceOnlyIdentityHintBehavesLikeNoHint() {
        let left = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.hint",
            processID: 1,
            title: "Clock",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 100, y: 0, width: 24, height: 24),
            actionNames: ["AXPress"],
            identityHint: nil
        ))

        let right = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.hint",
            processID: 1,
            title: "Clock",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 100, y: 0, width: 24, height: 24),
            actionNames: ["AXPress"],
            identityHint: "   "
        ))

        XCTAssertEqual(left.persistentID, right.persistentID)
    }

    func testRecordCodableRoundTripPreservesIdentities() throws {
        let original = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.codable",
            processID: 7,
            title: "Clock",
            description: "Menu Bar Clock",
            role: "AXMenuBarItem",
            subrole: "AXStatusItem",
            frame: CGRect(x: 100, y: 0, width: 24, height: 24),
            actionNames: ["AXPress", "AXShowMenu"],
            identityHint: "primary"
        ))

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MenuBarItemRecord.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.persistentID, original.persistentID)
        XCTAssertEqual(decoded.runtimeID, original.runtimeID)
    }

    func testRuntimeIDDiffersForMissingFrameLabels() {
        let left = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.no-frame",
            processID: 1,
            title: "Clock",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: nil,
            actionNames: ["AXPress"]
        ))

        let right = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.no-frame",
            processID: 1,
            title: "Timer",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: nil,
            actionNames: ["AXPress"]
        ))

        XCTAssertNotEqual(left.runtimeID, right.runtimeID)
    }

    func testPersistentIDUsesIdentityHintToDifferentiateSiblingItems() {
        let left = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.siblings",
            processID: 1,
            title: "First",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 100, y: 0, width: 24, height: 24),
            actionNames: ["AXPress"],
            identityHint: "first-sibling"
        ))

        let right = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.siblings",
            processID: 1,
            title: "Second",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 120, y: 0, width: 24, height: 24),
            actionNames: ["AXPress"],
            identityHint: "second-sibling"
        ))

        XCTAssertNotEqual(left.persistentID, right.persistentID)
        XCTAssertNotEqual(left.runtimeID, right.runtimeID)
    }
}
