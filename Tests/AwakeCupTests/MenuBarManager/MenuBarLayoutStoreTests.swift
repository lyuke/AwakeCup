import CoreGraphics
import XCTest
@testable import AwakeCup

@MainActor
final class MenuBarLayoutStoreTests: XCTestCase {
    func testAssignStoresSectionAndRevealsItOnReload() {
        let persistence = InMemoryLayoutPersistence()
        let firstStore = MenuBarLayoutStore(persistence: persistence)
        firstStore.assign(.hidden, to: "clock")

        let secondStore = MenuBarLayoutStore(persistence: persistence)

        XCTAssertEqual(secondStore.configuration.assignments["clock"], .hidden)
    }

    func testOrderedItemsRespectsSavedOrderWithinSection() {
        let persistence = InMemoryLayoutPersistence()
        let store = MenuBarLayoutStore(persistence: persistence)
        let one = MenuBarItemRecord(snapshot: .init(bundleIdentifier: "a", processID: 1, title: "One", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 10, y: 0, width: 20, height: 24), actionNames: ["AXPress"]))
        let two = MenuBarItemRecord(snapshot: .init(bundleIdentifier: "b", processID: 2, title: "Two", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 40, y: 0, width: 20, height: 24), actionNames: ["AXPress"]))

        store.assign(.hidden, to: two.persistentID)
        store.assign(.hidden, to: one.persistentID)
        store.updateOrder(for: .hidden, ids: [two.persistentID, one.persistentID])

        let inventory = [one, two]

        let hidden = store.orderedItems(inventory: inventory, section: .hidden)

        XCTAssertEqual(hidden.map(\.displayName), ["Two", "One"])
    }

    func testUnassignedItemsDefaultToAlwaysVisible() {
        let store = MenuBarLayoutStore(persistence: InMemoryLayoutPersistence())
        let inventory = [
            MenuBarItemRecord(snapshot: .init(bundleIdentifier: "a", processID: 1, title: "One", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 10, y: 0, width: 20, height: 24), actionNames: ["AXPress"])),
        ]

        let visible = store.orderedItems(inventory: inventory, section: .alwaysVisible)

        XCTAssertEqual(visible.map(\.displayName), ["One"])
    }
}
