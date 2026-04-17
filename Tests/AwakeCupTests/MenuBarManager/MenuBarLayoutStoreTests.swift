import Foundation
import CoreGraphics
import XCTest
@testable import AwakeCup

final class InMemoryLayoutPersistence: MenuBarLayoutPersisting {
    private var storage: [String: Data] = [:]

    func loadData(forKey key: String) -> Data? {
        storage[key]
    }

    func saveData(_ data: Data, forKey key: String) {
        storage[key] = data
    }
}

final class CorruptLayoutPersistence: MenuBarLayoutPersisting {
    func loadData(forKey key: String) -> Data? {
        Data("not-json".utf8)
    }

    func saveData(_ data: Data, forKey key: String) {}
}

@MainActor
final class MenuBarLayoutStoreTests: XCTestCase {
    func testAssignUsesPersistentIDAndRevealsItOnReload() {
        let persistence = InMemoryLayoutPersistence()
        let record = MenuBarItemRecord(snapshot: .init(bundleIdentifier: "com.example.clock", processID: 1, title: "Clock", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 10, y: 0, width: 20, height: 24), actionNames: ["AXPress"]))
        let firstStore = MenuBarLayoutStore(persistence: persistence)
        firstStore.assign(.hidden, toPersistentID: record.persistentID)

        let secondStore = MenuBarLayoutStore(persistence: persistence)

        XCTAssertEqual(secondStore.configuration.assignments[record.persistentID], .hidden)
    }

    func testPersistedLayoutUsesPersistentIDAcrossRuntimeChanges() {
        let persistence = InMemoryLayoutPersistence()
        let store = MenuBarLayoutStore(persistence: persistence)
        let recordA = MenuBarItemRecord(snapshot: .init(bundleIdentifier: "com.example.clock", processID: 1, title: "Clock", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 10, y: 0, width: 20, height: 24), actionNames: ["AXPress"]))
        let recordB = MenuBarItemRecord(snapshot: .init(bundleIdentifier: "com.example.clock", processID: 2, title: "Timer", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 200, y: 0, width: 30, height: 24), actionNames: ["AXPress", "AXShowMenu"]))

        XCTAssertEqual(recordA.persistentID, recordB.persistentID)
        XCTAssertNotEqual(recordA.runtimeID, recordB.runtimeID)

        store.assign(.hidden, toPersistentID: recordA.persistentID)
        store.updateOrder(for: .hidden, persistentIDs: [recordA.persistentID])

        let reloadedStore = MenuBarLayoutStore(persistence: persistence)

        XCTAssertEqual(reloadedStore.section(for: recordB), .hidden)
        XCTAssertEqual(reloadedStore.orderedItems(inventory: [recordB], section: .hidden).map(\.displayName), ["Timer"])
    }

    func testOrderedItemsRespectsSavedOrderWithinSection() {
        let persistence = InMemoryLayoutPersistence()
        let store = MenuBarLayoutStore(persistence: persistence)
        let one = MenuBarItemRecord(snapshot: .init(bundleIdentifier: "a", processID: 1, title: "One", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 10, y: 0, width: 20, height: 24), actionNames: ["AXPress"]))
        let two = MenuBarItemRecord(snapshot: .init(bundleIdentifier: "b", processID: 2, title: "Two", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 40, y: 0, width: 20, height: 24), actionNames: ["AXPress"]))

        store.assign(.hidden, toPersistentID: two.persistentID)
        store.assign(.hidden, toPersistentID: one.persistentID)
        store.updateOrder(for: .hidden, persistentIDs: [two.persistentID, one.persistentID])

        let inventory = [one, two]
        let reloadedStore = MenuBarLayoutStore(persistence: persistence)

        XCTAssertEqual(reloadedStore.configuration.orderBySection[.hidden], [two.persistentID, one.persistentID])

        let hidden = reloadedStore.orderedItems(inventory: inventory, section: .hidden)

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

    func testCorruptPersistedJSONFallsBackToDefaultConfiguration() {
        let store = MenuBarLayoutStore(persistence: CorruptLayoutPersistence())

        XCTAssertEqual(store.configuration, MenuBarLayoutConfiguration())
    }
}
