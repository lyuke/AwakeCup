import CoreGraphics
import XCTest
@testable import AwakeCup

@MainActor
final class MenuBarManagerViewModelTests: XCTestCase {
    func testAutoCollapsedExpandedStripDismissesOverlay() {
        let permission = AccessibilityPermissionController(checker: StubAccessibilityTrustChecker(responses: [true, true, true]))
        let hidden = makeRecord(
            bundleIdentifier: "com.example.hidden",
            processID: 2,
            title: "Hidden",
            originX: 40,
            actionNames: ["AXPress"]
        )
        let reader = StubMenuBarAXReader(records: [hidden])
        let inventory = MenuBarInventoryService(reader: reader)
        let layout = MenuBarLayoutStore(persistence: InMemoryMenuBarLayoutPersistence())
        layout.assign(.hidden, toPersistentID: hidden.persistentID)
        let presentation = MenuBarPresentationController()
        presentation.configuration = MenuBarPresentationConfiguration(
            preferredRevealMode: .expandedStrip,
            autoCollapseAfter: 0.01
        )
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

        XCTAssertEqual(overlay.lastPresentedStripIDs, [hidden.id])

        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertNil(presentation.state.activeSurface)
        XCTAssertEqual(overlay.lastPresentedStripIDs, [])
        XCTAssertGreaterThanOrEqual(overlay.dismissExpandedStripCalls, 1)
    }

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
        XCTAssertEqual(viewModel.alwaysVisibleItems.map(\.displayName), ["Visible", "Unmanaged"])
        XCTAssertEqual(viewModel.hiddenItems.map(\.displayName), ["Hidden"])
        XCTAssertEqual(viewModel.unmanagedItems.map(\.displayName), ["Unmanaged"])
        XCTAssertEqual(overlay.lastHiddenMaskIDs, [hidden.id])
    }

    func testRefreshHidesHiddenMaskWhenHiddenItemFrameIsUnavailable() {
        let permission = AccessibilityPermissionController(checker: StubAccessibilityTrustChecker(responses: [true, true]))
        let hidden = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.hidden",
            processID: 2,
            title: "Hidden",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: nil,
            actionNames: ["AXPress"]
        ))
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

        XCTAssertEqual(overlay.hideHiddenMaskCalls, 1)
        XCTAssertEqual(overlay.lastHiddenMaskIDs, [])
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

    func testRevealHiddenItemsButtonIsHiddenForPanelMode() {
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
        presentation.configuration.preferredRevealMode = .panel
        let overlay = StubMenuBarOverlayController()
        let viewModel = MenuBarManagerViewModel(
            permission: permission,
            inventory: inventory,
            layout: layout,
            presentation: presentation,
            overlay: overlay
        )

        viewModel.refresh()

        XCTAssertFalse(viewModel.shouldShowRevealHiddenItemsButton)
        XCTAssertFalse(viewModel.canRevealHiddenItemsInPreferredMode)
    }

    func testRevealHiddenItemsButtonIsDisabledWhenExpandedStripCannotBePresented() {
        let permission = AccessibilityPermissionController(checker: StubAccessibilityTrustChecker(responses: [true, true]))
        let hidden = makeRecord(
            bundleIdentifier: "com.example.hidden",
            processID: 2,
            title: "Hidden",
            originX: 40,
            actionNames: []
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

        XCTAssertTrue(viewModel.shouldShowRevealHiddenItemsButton)
        XCTAssertFalse(viewModel.canRevealHiddenItemsInPreferredMode)
    }

    func testExpandedStripForwardsPressedItemThroughViewModel() {
        let permission = AccessibilityPermissionController(checker: StubAccessibilityTrustChecker(responses: [true, true]))
        let hidden = makeRecord(
            bundleIdentifier: "com.example.hidden",
            processID: 2,
            title: "Hidden",
            originX: 40,
            actionNames: ["AXPress"]
        )
        let reader = StubMenuBarAXReader(records: [hidden])
        let inventory = MenuBarInventoryService(reader: reader)
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
        overlay.simulatePresentedStripPress(for: hidden)

        XCTAssertEqual(reader.pressedIDs, [hidden.id])
        XCTAssertNil(viewModel.inventoryErrorMessage)
    }

    func testExpandedStripDismissesWhenForwardedPressFails() {
        let permission = AccessibilityPermissionController(checker: StubAccessibilityTrustChecker(responses: [true, true]))
        let hidden = makeRecord(
            bundleIdentifier: "com.example.hidden",
            processID: 2,
            title: "Hidden",
            originX: 40,
            actionNames: ["AXPress"]
        )
        let reader = StubMenuBarAXReader(records: [hidden])
        reader.pressError = MenuBarAXClientError.pressFailed(hidden.id)
        let inventory = MenuBarInventoryService(reader: reader)
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
        overlay.simulatePresentedStripPress(for: hidden)

        XCTAssertNil(presentation.state.activeSurface)
        XCTAssertEqual(overlay.lastPresentedStripIDs, [])
        XCTAssertGreaterThanOrEqual(overlay.dismissExpandedStripCalls, 1)
        XCTAssertEqual(
            viewModel.inventoryErrorMessage,
            "Unable to press menu bar item \(hidden.id)."
        )
    }

    func testShowHiddenItemsFallsBackToPanelWhenHiddenItemFrameIsUnavailable() {
        let permission = AccessibilityPermissionController(checker: StubAccessibilityTrustChecker(responses: [true, true]))
        let hidden = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "com.example.hidden",
            processID: 2,
            title: "Hidden",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: nil,
            actionNames: ["AXPress"]
        ))
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

        XCTAssertEqual(presentation.state.activeSurface, .panel)
        XCTAssertEqual(overlay.lastPresentedStripIDs, [])
    }

    func testShowHiddenItemsFallsBackToPanelWhenHiddenItemCannotBePressed() {
        let permission = AccessibilityPermissionController(checker: StubAccessibilityTrustChecker(responses: [true, true]))
        let hidden = makeRecord(
            bundleIdentifier: "com.example.hidden",
            processID: 2,
            title: "Hidden",
            originX: 40,
            actionNames: []
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

        XCTAssertEqual(presentation.state.activeSurface, .panel)
        XCTAssertEqual(overlay.lastPresentedStripIDs, [])
    }

    func testSetPreferredRevealModeDismissesExpandedStripWhenSwitchingBackToPanel() {
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
        let dismissCallsBeforeSwitch = overlay.dismissExpandedStripCalls
        viewModel.setPreferredRevealMode(.panel)

        XCTAssertNil(presentation.state.activeSurface)
        XCTAssertEqual(overlay.lastPresentedStripIDs, [])
        XCTAssertEqual(overlay.dismissExpandedStripCalls, dismissCallsBeforeSwitch + 1)
        XCTAssertEqual(viewModel.preferredRevealMode, .panel)
    }

    func testRefreshStopsInventoryObservationWhenPermissionIsRevoked() {
        let permission = AccessibilityPermissionController(checker: StubAccessibilityTrustChecker(responses: [true, true, false]))
        let hidden = makeRecord(
            bundleIdentifier: "com.example.hidden",
            processID: 2,
            title: "Hidden",
            originX: 40,
            actionNames: ["AXPress"]
        )
        let reader = StubMenuBarAXReader(records: [hidden])
        let inventory = MenuBarInventoryService(reader: reader)
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

        XCTAssertEqual(reader.startObservationProcessIDs, [Set([hidden.processID])])
        XCTAssertEqual(reader.stopObservationCalls, 0)
        XCTAssertEqual(inventory.records.map(\.displayName), ["Hidden"])

        viewModel.refresh()

        XCTAssertFalse(viewModel.canManageItems)
        XCTAssertEqual(reader.stopObservationCalls, 1)
        XCTAssertTrue(inventory.records.isEmpty)
    }

    func testPressStoresReadableFailureMessage() {
        let permission = AccessibilityPermissionController(checker: StubAccessibilityTrustChecker(responses: [true, true]))
        let hidden = makeRecord(
            bundleIdentifier: "com.example.hidden",
            processID: 2,
            title: "Hidden",
            originX: 40,
            actionNames: ["AXPress"]
        )
        let reader = StubMenuBarAXReader(records: [hidden])
        reader.pressError = MenuBarAXClientError.pressFailed(hidden.id)
        let inventory = MenuBarInventoryService(reader: reader)
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
        XCTAssertNil(viewModel.inventoryErrorMessage)

        viewModel.press(hidden)

        XCTAssertEqual(
            viewModel.inventoryErrorMessage,
            "Unable to press menu bar item \(hidden.id)."
        )
        XCTAssertEqual(viewModel.hiddenItems.map(\.displayName), ["Hidden"])
    }

    func testHideOtherVisibleItemsMovesOnlyNonAppItemsToHidden() {
        let permission = AccessibilityPermissionController(checker: StubAccessibilityTrustChecker(responses: [true, true, true]))
        let appItem = makeRecord(
            bundleIdentifier: "com.awakecup.app",
            processID: 1,
            title: "AwakeCup",
            originX: 10,
            actionNames: ["AXPress"]
        )
        let externalItem = makeRecord(
            bundleIdentifier: "com.example.clock",
            processID: 2,
            title: "Clock",
            originX: 40,
            actionNames: []
        )
        let inventory = MenuBarInventoryService(reader: StubMenuBarAXReader(records: [appItem, externalItem]))
        let layout = MenuBarLayoutStore(persistence: InMemoryMenuBarLayoutPersistence())
        let presentation = MenuBarPresentationController()
        let overlay = StubMenuBarOverlayController()
        let viewModel = MenuBarManagerViewModel(
            permission: permission,
            inventory: inventory,
            layout: layout,
            presentation: presentation,
            overlay: overlay,
            currentAppBundleIdentifier: "com.awakecup.app"
        )

        viewModel.refresh()
        viewModel.hideOtherVisibleItems()

        XCTAssertEqual(viewModel.alwaysVisibleItems.map(\.displayName), ["AwakeCup"])
        XCTAssertEqual(viewModel.hiddenItems.map(\.displayName), ["Clock"])
        XCTAssertEqual(layout.section(for: appItem), .alwaysVisible)
        XCTAssertEqual(layout.section(for: externalItem), .hidden)
        XCTAssertEqual(overlay.lastHiddenMaskIDs, [externalItem.id])
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
    private var presentedStripPressHandler: ((MenuBarItemRecord) -> Void)?

    func updateHiddenMask(for hiddenItems: [MenuBarItemRecord]) {
        lastHiddenMaskIDs = hiddenItems.map(\.id)
    }

    func hideHiddenMask() {
        hideHiddenMaskCalls += 1
        lastHiddenMaskIDs = []
    }

    func presentExpandedStrip(
        for hiddenItems: [MenuBarItemRecord],
        onPress: @escaping (MenuBarItemRecord) -> Void
    ) {
        lastPresentedStripIDs = hiddenItems.map(\.id)
        presentedStripPressHandler = onPress
    }

    func dismissExpandedStrip() {
        dismissExpandedStripCalls += 1
        lastPresentedStripIDs = []
        presentedStripPressHandler = nil
    }

    func simulatePresentedStripPress(for item: MenuBarItemRecord) {
        presentedStripPressHandler?(item)
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
    private(set) var startObservationProcessIDs: [Set<Int32>] = []
    private(set) var stopObservationCalls = 0
    var pressError: Error?

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
                frame: $0.hasKnownFrame ? $0.frame : nil,
                actionNames: $0.actionNames
            )
        }
    }

    func press(_ runtimeID: String) throws {
        if let pressError {
            throw pressError
        }
        pressedIDs.append(runtimeID)
    }

    func startObserving(processIDs: Set<Int32>, onChange: @escaping () -> Void) -> Set<Int32> {
        startObservationProcessIDs.append(processIDs)
        return processIDs
    }

    func stopObserving() {
        stopObservationCalls += 1
    }
}
