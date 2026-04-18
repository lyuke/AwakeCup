import CoreGraphics
import XCTest
@testable import AwakeCup

@MainActor
final class MenuBarManagerViewModelTests: XCTestCase {
    func testRefreshBuildsVisibleHiddenAndUnmanagedCollections() {
        let permission = AccessibilityPermissionController(checker: StubAccessibilityTrustChecker(responses: [true, true]))
        let visible = makeRecord(
            bundleIdentifier: "com.example.visible",
            processID: 1,
            title: "Visible",
            originX: 10,
            actionNames: ["AXPress"]
        )
        let hidden = makeRecord(
            bundleIdentifier: "com.example.hidden",
            processID: 2,
            title: "Hidden",
            originX: 40,
            actionNames: ["AXPress"]
        )
        let unmanaged = makeRecord(
            bundleIdentifier: "com.example.unmanaged",
            processID: 3,
            title: "Unmanaged",
            originX: 70,
            actionNames: []
        )
        let inventory = MenuBarInventoryService(reader: StubMenuBarAXReader(records: [hidden, unmanaged, visible]))
        let layout = MenuBarLayoutStore(persistence: InMemoryMenuBarLayoutPersistence())
        layout.assign(.hidden, toPersistentID: hidden.persistentID)
        let presentation = MenuBarPresentationController()
        let overlay = StubMenuBarOverlayController()
        let viewModel = MenuBarManagerViewModel(
            permission: permission,
            inventory: inventory,
            layout: layout,
            presentation: presentation,
            overlay: overlay
        )

        viewModel.refresh()

        XCTAssertTrue(viewModel.canManageItems)
        XCTAssertEqual(viewModel.alwaysVisibleItems.map(\.displayName), ["Visible"])
        XCTAssertEqual(viewModel.hiddenItems.map(\.displayName), ["Hidden"])
        XCTAssertEqual(viewModel.unmanagedItems.map(\.displayName), ["Unmanaged"])
        XCTAssertEqual(overlay.lastHiddenMaskIDs, [hidden.id])
    }

    func testRefreshClearsCollectionsAndOverlaysWhenPermissionIsDenied() {
        let permission = AccessibilityPermissionController(checker: StubAccessibilityTrustChecker(responses: [false, false]))
        let hidden = makeRecord(
            bundleIdentifier: "com.example.hidden",
            processID: 2,
            title: "Hidden",
            originX: 40,
            actionNames: ["AXPress"]
        )
        let inventory = MenuBarInventoryService(reader: StubMenuBarAXReader(records: [hidden]))
        let layout = MenuBarLayoutStore(persistence: InMemoryMenuBarLayoutPersistence())
        layout.assign(.hidden, toPersistentID: hidden.persistentID)
        let presentation = MenuBarPresentationController()
        let overlay = StubMenuBarOverlayController()
        let viewModel = MenuBarManagerViewModel(
            permission: permission,
            inventory: inventory,
            layout: layout,
            presentation: presentation,
            overlay: overlay
        )

        viewModel.refresh()

        XCTAssertFalse(viewModel.canManageItems)
        XCTAssertTrue(viewModel.alwaysVisibleItems.isEmpty)
        XCTAssertTrue(viewModel.hiddenItems.isEmpty)
        XCTAssertTrue(viewModel.unmanagedItems.isEmpty)
        XCTAssertEqual(overlay.hideHiddenMaskCalls, 1)
        XCTAssertEqual(overlay.dismissExpandedStripCalls, 1)
    }

    func testShowHiddenItemsPresentsExpandedStripWhenPreferredSurfaceIsActive() {
        let permission = AccessibilityPermissionController(checker: StubAccessibilityTrustChecker(responses: [true, true]))
        let hidden = makeRecord(
            bundleIdentifier: "com.example.hidden",
            processID: 2,
            title: "Hidden",
            originX: 40,
            actionNames: ["AXPress"]
        )
        let inventory = MenuBarInventoryService(reader: StubMenuBarAXReader(records: [hidden]))
        let layout = MenuBarLayoutStore(persistence: InMemoryMenuBarLayoutPersistence())
        layout.assign(.hidden, toPersistentID: hidden.persistentID)
        let presentation = MenuBarPresentationController()
        presentation.configuration.preferredRevealMode = .expandedStrip
        let overlay = StubMenuBarOverlayController()
        let viewModel = MenuBarManagerViewModel(
            permission: permission,
            inventory: inventory,
            layout: layout,
            presentation: presentation,
            overlay: overlay
        )

        viewModel.refresh()
        viewModel.showHiddenItems()

        XCTAssertEqual(presentation.state.activeSurface, .expandedStrip)
        XCTAssertEqual(overlay.lastPresentedStripIDs, [hidden.id])
    }

    private func makeRecord(
        bundleIdentifier: String,
        processID: Int32,
        title: String,
        originX: CGFloat,
        actionNames: [String]
    ) -> MenuBarItemRecord {
        MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: bundleIdentifier,
            processID: processID,
            title: title,
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: originX, y: 0, width: 20, height: 24),
            actionNames: actionNames
        ))
    }
}

private final class InMemoryMenuBarLayoutPersistence: MenuBarLayoutPersisting {
    private var storage: [String: Data] = [:]

    func loadData(forKey key: String) -> Data? {
        storage[key]
    }

    func saveData(_ data: Data, forKey key: String) {
        storage[key] = data
    }
}

@MainActor
private final class StubMenuBarOverlayController: MenuBarOverlayControlling {
    private(set) var lastHiddenMaskIDs: [String] = []
    private(set) var lastPresentedStripIDs: [String] = []
    private(set) var hideHiddenMaskCalls = 0
    private(set) var dismissExpandedStripCalls = 0

    func updateHiddenMask(for hiddenItems: [MenuBarItemRecord]) {
        lastHiddenMaskIDs = hiddenItems.map(\.id)
    }

    func hideHiddenMask() {
        hideHiddenMaskCalls += 1
        lastHiddenMaskIDs = []
    }

    func presentExpandedStrip(for hiddenItems: [MenuBarItemRecord]) {
        lastPresentedStripIDs = hiddenItems.map(\.id)
    }

    func dismissExpandedStrip() {
        dismissExpandedStripCalls += 1
        lastPresentedStripIDs = []
    }
}

private final class StubAccessibilityTrustChecker: AccessibilityTrustChecking {
    private var responses: [Bool]

    init(responses: [Bool]) {
        self.responses = responses
    }

    func isTrusted(prompt: Bool) -> Bool {
        guard !responses.isEmpty else {
            return false
        }
        return responses.removeFirst()
    }
}

@MainActor
private final class StubMenuBarAXReader: MenuBarAXReading {
    private let records: [MenuBarItemRecord]
    private(set) var pressedIDs: [String] = []

    init(records: [MenuBarItemRecord]) {
        self.records = records
    }

    func fetchSnapshots() throws -> [MenuBarItemSnapshot] {
        records.map {
            MenuBarItemSnapshot(
                bundleIdentifier: $0.bundleIdentifier,
                processID: $0.processID,
                title: $0.displayName,
                description: nil,
                role: $0.axRole,
                subrole: $0.axSubrole,
                frame: $0.frame,
                actionNames: $0.actionNames
            )
        }
    }

    func press(_ runtimeID: String) throws {
        pressedIDs.append(runtimeID)
    }

    func startObserving(processIDs: Set<Int32>, onChange: @escaping () -> Void) {}

    func stopObserving() {}
}
