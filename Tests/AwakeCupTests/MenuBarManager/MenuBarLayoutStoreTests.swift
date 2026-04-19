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

        let recordA = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.alpha",
            processID: 1,
            title: "Alpha",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 220, y: 0, width: 20, height: 24),
            actionNames: ["AXPress"]
        ))
        let recordB = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.beta",
            processID: 2,
            title: "Beta",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 40, y: 0, width: 20, height: 24),
            actionNames: ["AXPress"]
        ))

        let recordAPrime = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.alpha",
            processID: 11,
            title: "Alpha Prime",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 40, y: 0, width: 20, height: 24),
            actionNames: ["AXPress", "AXShowMenu"]
        ))
        let recordBPrime = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.beta",
            processID: 22,
            title: "Beta Prime",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 220, y: 0, width: 20, height: 24),
            actionNames: ["AXPress", "AXShowMenu"]
        ))

        XCTAssertEqual(recordA.persistentID, recordAPrime.persistentID)
        XCTAssertEqual(recordB.persistentID, recordBPrime.persistentID)
        XCTAssertNotEqual(recordA.runtimeID, recordAPrime.runtimeID)
        XCTAssertNotEqual(recordB.runtimeID, recordBPrime.runtimeID)

        store.assign(.hidden, toPersistentID: recordA.persistentID)
        store.assign(.hidden, toPersistentID: recordB.persistentID)
        store.updateOrder(for: .hidden, persistentIDs: [recordA.persistentID, recordB.persistentID])

        let reloadedStore = MenuBarLayoutStore(persistence: persistence)
        let inventory = [recordAPrime, recordBPrime]

        XCTAssertEqual(reloadedStore.section(for: recordAPrime), .hidden)
        XCTAssertEqual(reloadedStore.section(for: recordBPrime), .hidden)
        XCTAssertEqual(reloadedStore.configuration.orderBySection[.hidden], [recordA.persistentID, recordB.persistentID])
        XCTAssertEqual(reloadedStore.orderedItems(inventory: inventory, section: .hidden).map(\.displayName), ["Alpha Prime", "Beta Prime"])
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

    func testOrderedItemsPlacesUnknownFramesAfterKnownPositionsWhenNoSavedOrderExists() {
        let store = MenuBarLayoutStore(persistence: InMemoryLayoutPersistence())
        let known = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "known",
            processID: 1,
            title: "Known",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 10, y: 0, width: 20, height: 24),
            actionNames: ["AXPress"]
        ))
        let unknown = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "unknown",
            processID: 2,
            title: "Unknown",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: nil,
            actionNames: ["AXPress"]
        ))

        store.assign(.hidden, toPersistentID: known.persistentID)
        store.assign(.hidden, toPersistentID: unknown.persistentID)

        let ordered = store.orderedItems(inventory: [unknown, known], section: .hidden)

        XCTAssertEqual(ordered.map(\.displayName), ["Known", "Unknown"])
        XCTAssertEqual(ordered.map(\.hasKnownFrame), [true, false])
    }

    func testAssignBatchUpdatesAllProvidedPersistentIDs() {
        let store = MenuBarLayoutStore(persistence: InMemoryLayoutPersistence())
        let first = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "first",
            processID: 1,
            title: "First",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 10, y: 0, width: 20, height: 24),
            actionNames: ["AXPress"]
        ))
        let second = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "second",
            processID: 2,
            title: "Second",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 40, y: 0, width: 20, height: 24),
            actionNames: ["AXPress"]
        ))

        store.assign(.hidden, toPersistentIDs: [first.persistentID, second.persistentID])

        XCTAssertEqual(store.section(for: first), .hidden)
        XCTAssertEqual(store.section(for: second), .hidden)
    }

    func testCorruptPersistedJSONFallsBackToDefaultConfiguration() {
        let store = MenuBarLayoutStore(persistence: CorruptLayoutPersistence())

        XCTAssertEqual(store.configuration, MenuBarLayoutConfiguration())
    }
}
