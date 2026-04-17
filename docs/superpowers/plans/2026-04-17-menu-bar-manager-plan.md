# Menu Bar Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a menu bar manager that can discover third-party menu bar extras, let the user choose which ones stay visible, and expose hidden items through both a panel and a temporary expanded strip.

**Architecture:** Keep the existing AwakeCup sleep-prevention flow intact and add the menu bar manager as a new set of focused files under `Sources/AwakeCup/MenuBarManager/`. Build the feature in three layers: pure models and persistence first, Accessibility permission and live inventory second, then SwiftUI/AppKit integration for the menu bar panel, settings window, and expanded-strip overlay.

**Tech Stack:** SwiftUI, AppKit, ApplicationServices Accessibility APIs (`AXUIElement`, `AXObserver`), XCTest, JSON persistence, `@AppStorage`

---

## Planned File Structure

- Modify: `Package.swift`
  Adds `ApplicationServices` so the target can compile Accessibility-driven code.
- Modify: `Sources/AwakeCup/AwakeCup.swift`
  Keeps the existing caffeine UI and icon logic, but wires in the new menu bar manager state, settings window, and window-style `MenuBarExtra`.
- Create: `Sources/AwakeCup/MenuBarManager/MenuBarItemRecord.swift`
  Pure models for discovered items, fingerprinting, sectioning, and unsupported-item classification.
- Create: `Sources/AwakeCup/MenuBarManager/MenuBarLayoutStore.swift`
  JSON-backed assignment/order/reveal-mode persistence plus reconciliation helpers.
- Create: `Sources/AwakeCup/MenuBarManager/AccessibilityPermissionController.swift`
  Trusted-client state and prompt flow around `AXIsProcessTrustedWithOptions`.
- Create: `Sources/AwakeCup/MenuBarManager/MenuBarAXClient.swift`
  Live Accessibility traversal and observer registration against app extras menu bars.
- Create: `Sources/AwakeCup/MenuBarManager/MenuBarInventoryService.swift`
  Observable inventory service that refreshes records and handles AX read failures.
- Create: `Sources/AwakeCup/MenuBarManager/MenuBarPresentationController.swift`
  Pure reveal-state controller for panel vs expanded-strip behavior and auto-collapse.
- Create: `Sources/AwakeCup/MenuBarManager/MenuBarOverlayController.swift`
  AppKit windows that mask hidden items and render the temporary expanded strip.
- Create: `Sources/AwakeCup/MenuBarManager/MenuBarManagerViewModel.swift`
  Bridges permission, inventory, layout, and presentation state into SwiftUI.
- Create: `Sources/AwakeCup/MenuBarManager/MenuBarManagerSettingsView.swift`
  Primary management UI for `Always Visible` and `Hidden`.
- Create: `Sources/AwakeCup/MenuBarManager/MenuBarExtraContentView.swift`
  Window-style menu bar panel that combines current AwakeCup controls with hidden-item actions.
- Create: `Tests/AwakeCupTests/MenuBarManager/MenuBarItemRecordTests.swift`
- Create: `Tests/AwakeCupTests/MenuBarManager/MenuBarLayoutStoreTests.swift`
- Create: `Tests/AwakeCupTests/MenuBarManager/AccessibilityPermissionControllerTests.swift`
- Create: `Tests/AwakeCupTests/MenuBarManager/MenuBarInventoryServiceTests.swift`
- Create: `Tests/AwakeCupTests/MenuBarManager/MenuBarPresentationControllerTests.swift`
- Create: `Tests/AwakeCupTests/MenuBarManager/MenuBarManagerViewModelTests.swift`

## Task 1: Add the item model and unsupported-item classification

**Files:**
- Create: `Sources/AwakeCup/MenuBarManager/MenuBarItemRecord.swift`
- Test: `Tests/AwakeCupTests/MenuBarManager/MenuBarItemRecordTests.swift`

- [ ] **Step 1: Write the failing tests for display-name fallback, stable IDs, and unsupported items**

```swift
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
```

- [ ] **Step 2: Run the focused test target and verify it fails because the new model does not exist yet**

Run: `swift test --filter MenuBarItemRecordTests`

Expected: build failure mentioning missing types like `MenuBarItemSnapshot` and `MenuBarItemRecord`.

- [ ] **Step 3: Implement the pure item model**

```swift
import CoreGraphics
import Foundation

enum MenuBarItemSection: String, Codable, CaseIterable, Equatable {
    case alwaysVisible
    case hidden
}

enum MenuBarItemManageability: Codable, Equatable {
    case manageable
    case unmanaged(reason: String)
}

struct MenuBarItemSnapshot: Equatable {
    let bundleIdentifier: String
    let processID: Int32
    let title: String?
    let description: String?
    let role: String?
    let subrole: String?
    let frame: CGRect?
    let actionNames: [String]
}

struct MenuBarItemRecord: Identifiable, Codable, Equatable {
    let id: String
    let bundleIdentifier: String
    let processID: Int32
    let displayName: String
    let axRole: String
    let axSubrole: String?
    let frame: CGRect
    let actionNames: [String]
    let manageability: MenuBarItemManageability

    init(snapshot: MenuBarItemSnapshot) {
        let role = snapshot.role ?? "AXUnknown"
        let frame = snapshot.frame ?? .zero
        let displayName = snapshot.title?.nonEmpty
            ?? snapshot.description?.nonEmpty
            ?? snapshot.bundleIdentifier

        let manageability: MenuBarItemManageability
        if snapshot.frame == nil {
            manageability = .unmanaged(reason: "Missing frame")
        } else if snapshot.actionNames.contains("AXPress") {
            manageability = .manageable
        } else {
            manageability = .unmanaged(reason: "Missing AXPress action")
        }

        let coarseX = Int(frame.minX.rounded())
        let coarseWidth = Int(frame.width.rounded())

        self.id = [
            snapshot.bundleIdentifier,
            role,
            snapshot.subrole ?? "-",
            displayName,
            snapshot.actionNames.sorted().joined(separator: ","),
            "\(coarseX)",
            "\(coarseWidth)",
        ].joined(separator: "|")
        self.bundleIdentifier = snapshot.bundleIdentifier
        self.processID = snapshot.processID
        self.displayName = displayName
        self.axRole = role
        self.axSubrole = snapshot.subrole
        self.frame = frame
        self.actionNames = snapshot.actionNames.sorted()
        self.manageability = manageability
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
```

- [ ] **Step 4: Re-run the tests and verify they pass**

Run: `swift test --filter MenuBarItemRecordTests`

Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit the model**

```bash
git add Sources/AwakeCup/MenuBarManager/MenuBarItemRecord.swift Tests/AwakeCupTests/MenuBarManager/MenuBarItemRecordTests.swift
git commit -m "feat: add menu bar item record model"
```

---

## Task 2: Add persisted layout state and reconciliation

**Files:**
- Create: `Sources/AwakeCup/MenuBarManager/MenuBarLayoutStore.swift`
- Test: `Tests/AwakeCupTests/MenuBarManager/MenuBarLayoutStoreTests.swift`

- [ ] **Step 1: Write the failing tests for assignment persistence and section ordering**

```swift
import CoreGraphics
import XCTest
@testable import AwakeCup

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
        store.assign(.hidden, to: "two")
        store.assign(.hidden, to: "one")
        store.updateOrder(for: .hidden, ids: ["two", "one"])

        let inventory = [
            MenuBarItemRecord(snapshot: .init(bundleIdentifier: "a", processID: 1, title: "One", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 10, y: 0, width: 20, height: 24), actionNames: ["AXPress"])),
            MenuBarItemRecord(snapshot: .init(bundleIdentifier: "b", processID: 2, title: "Two", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 40, y: 0, width: 20, height: 24), actionNames: ["AXPress"])),
        ]

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
```

- [ ] **Step 2: Run the focused tests and verify they fail because the store does not exist yet**

Run: `swift test --filter MenuBarLayoutStoreTests`

Expected: build failure mentioning missing `MenuBarLayoutStore` and `InMemoryLayoutPersistence`.

- [ ] **Step 3: Implement the layout store and JSON persistence**

```swift
import Foundation

enum HiddenItemRevealMode: String, Codable, CaseIterable {
    case panel
    case expandedStrip
}

struct MenuBarLayoutConfiguration: Codable, Equatable {
    var assignments: [String: MenuBarItemSection] = [:]
    var orderBySection: [MenuBarItemSection: [String]] = [:]
    var defaultRevealMode: HiddenItemRevealMode = .panel
    var autoCollapseSeconds: TimeInterval = 8
    var isEnabled: Bool = true
}

protocol MenuBarLayoutPersisting {
    func loadData(forKey key: String) -> Data?
    func saveData(_ data: Data, forKey key: String)
}

struct UserDefaultsLayoutPersistence: MenuBarLayoutPersisting {
    let defaults: UserDefaults = .standard

    func loadData(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func saveData(_ data: Data, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

final class InMemoryLayoutPersistence: MenuBarLayoutPersisting {
    private var storage: [String: Data] = [:]

    func loadData(forKey key: String) -> Data? {
        storage[key]
    }

    func saveData(_ data: Data, forKey key: String) {
        storage[key] = data
    }
}

@MainActor
final class MenuBarLayoutStore: ObservableObject {
    @Published private(set) var configuration: MenuBarLayoutConfiguration

    private let persistence: MenuBarLayoutPersisting
    private let storageKey = "menuBarManagerLayout"

    init(persistence: MenuBarLayoutPersisting = UserDefaultsLayoutPersistence()) {
        self.persistence = persistence
        if let data = persistence.loadData(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(MenuBarLayoutConfiguration.self, from: data) {
            self.configuration = decoded
        } else {
            self.configuration = MenuBarLayoutConfiguration()
        }
    }

    func assign(_ section: MenuBarItemSection, to itemID: String) {
        configuration.assignments[itemID] = section
        persist()
    }

    func updateOrder(for section: MenuBarItemSection, ids: [String]) {
        configuration.orderBySection[section] = ids
        persist()
    }

    func setDefaultRevealMode(_ mode: HiddenItemRevealMode) {
        configuration.defaultRevealMode = mode
        persist()
    }

    func section(for item: MenuBarItemRecord) -> MenuBarItemSection {
        configuration.assignments[item.id] ?? .alwaysVisible
    }

    func orderedItems(inventory: [MenuBarItemRecord], section: MenuBarItemSection) -> [MenuBarItemRecord] {
        let records = inventory.filter { self.section(for: $0) == section }
        let order = configuration.orderBySection[section] ?? []

        return records.sorted { left, right in
            let leftIndex = order.firstIndex(of: left.id) ?? .max
            let rightIndex = order.firstIndex(of: right.id) ?? .max
            if leftIndex != rightIndex { return leftIndex < rightIndex }
            return left.frame.minX < right.frame.minX
        }
    }

    private func persist() {
        let data = try! JSONEncoder().encode(configuration)
        persistence.saveData(data, forKey: storageKey)
    }
}
```

- [ ] **Step 4: Re-run the layout tests and verify they pass**

Run: `swift test --filter MenuBarLayoutStoreTests`

Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit the store**

```bash
git add Sources/AwakeCup/MenuBarManager/MenuBarLayoutStore.swift Tests/AwakeCupTests/MenuBarManager/MenuBarLayoutStoreTests.swift
git commit -m "feat: add menu bar layout store"
```

---

## Task 3: Add Accessibility permission state and link `ApplicationServices`

**Files:**
- Modify: `Package.swift`
- Create: `Sources/AwakeCup/MenuBarManager/AccessibilityPermissionController.swift`
- Test: `Tests/AwakeCupTests/MenuBarManager/AccessibilityPermissionControllerTests.swift`

- [ ] **Step 1: Write the failing tests for permission refresh and prompt flow**

```swift
import XCTest
@testable import AwakeCup

@MainActor
final class AccessibilityPermissionControllerTests: XCTestCase {
    func testRefreshSetsGrantedWhenCheckerReturnsTrue() {
        let checker = StubAccessibilityTrustChecker(responses: [false, true])
        let controller = AccessibilityPermissionController(checker: checker)

        controller.refresh()
        XCTAssertEqual(controller.state, .denied)

        controller.refresh()
        XCTAssertEqual(controller.state, .granted)
    }

    func testRequestAccessPromptsAndLeavesDeniedWhenStillUntrusted() {
        let checker = StubAccessibilityTrustChecker(responses: [false])
        let controller = AccessibilityPermissionController(checker: checker)

        controller.requestAccess()

        XCTAssertEqual(controller.state, .denied)
        XCTAssertEqual(checker.promptCalls, 1)
    }
}
```

- [ ] **Step 2: Run the focused test target and verify it fails**

Run: `swift test --filter AccessibilityPermissionControllerTests`

Expected: build failure for missing `AccessibilityPermissionController` and `StubAccessibilityTrustChecker`.

- [ ] **Step 3: Implement the controller and add the missing framework link**

```swift
// Package.swift linker settings excerpt
.linkedFramework("ApplicationServices"),
```

```swift
import ApplicationServices
import Foundation

protocol AccessibilityTrustChecking {
    func isTrusted(prompt: Bool) -> Bool
}

struct LiveAccessibilityTrustChecker: AccessibilityTrustChecking {
    func isTrusted(prompt: Bool) -> Bool {
        let options: CFDictionary? = prompt
            ? [kAXTrustedCheckOptionPrompt as String: true] as CFDictionary
            : nil
        return AXIsProcessTrustedWithOptions(options)
    }
}

final class StubAccessibilityTrustChecker: AccessibilityTrustChecking {
    private var responses: [Bool]
    private(set) var promptCalls: Int = 0

    init(responses: [Bool]) {
        self.responses = responses
    }

    func isTrusted(prompt: Bool) -> Bool {
        if prompt { promptCalls += 1 }
        if responses.isEmpty { return false }
        return responses.removeFirst()
    }
}

@MainActor
final class AccessibilityPermissionController: ObservableObject {
    enum State: Equatable {
        case unknown
        case granted
        case denied
    }

    @Published private(set) var state: State = .unknown

    var canManageItems: Bool { state == .granted }

    private let checker: AccessibilityTrustChecking

    init(checker: AccessibilityTrustChecking = LiveAccessibilityTrustChecker()) {
        self.checker = checker
    }

    func refresh() {
        state = checker.isTrusted(prompt: false) ? .granted : .denied
    }

    func requestAccess() {
        state = checker.isTrusted(prompt: true) ? .granted : .denied
    }
}
```

- [ ] **Step 4: Re-run the permission tests and verify they pass**

Run: `swift test --filter AccessibilityPermissionControllerTests`

Expected: `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Commit the permission layer**

```bash
git add Package.swift Sources/AwakeCup/MenuBarManager/AccessibilityPermissionController.swift Tests/AwakeCupTests/MenuBarManager/AccessibilityPermissionControllerTests.swift
git commit -m "feat: add accessibility permission controller"
```

---

## Task 4: Add the live AX reader and observable inventory service

**Files:**
- Create: `Sources/AwakeCup/MenuBarManager/MenuBarAXClient.swift`
- Create: `Sources/AwakeCup/MenuBarManager/MenuBarInventoryService.swift`
- Test: `Tests/AwakeCupTests/MenuBarManager/MenuBarInventoryServiceTests.swift`

- [ ] **Step 1: Write the failing tests for sorting and error propagation**

```swift
import CoreGraphics
import XCTest
@testable import AwakeCup

final class MenuBarInventoryServiceTests: XCTestCase {
    @MainActor
    func testRefreshSortsRecordsByMenuBarPosition() {
        let reader = StubMenuBarAXReader(result: .success([
            .init(bundleIdentifier: "b", processID: 2, title: "Two", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 80, y: 0, width: 20, height: 24), actionNames: ["AXPress"]),
            .init(bundleIdentifier: "a", processID: 1, title: "One", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 20, y: 0, width: 20, height: 24), actionNames: ["AXPress"]),
        ]))
        let service = MenuBarInventoryService(reader: reader)

        service.refresh()

        XCTAssertEqual(service.records.map(\.displayName), ["One", "Two"])
        XCTAssertNil(service.lastRefreshError)
    }

    @MainActor
    func testRefreshStoresReadableErrorWhenReaderFails() {
        let reader = StubMenuBarAXReader(result: .failure(MenuBarAXClientError.permissionDenied))
        let service = MenuBarInventoryService(reader: reader)

        service.refresh()

        XCTAssertEqual(service.lastRefreshError, "Accessibility permission is required.")
    }

    @MainActor
    func testPressDelegatesToReader() throws {
        let record = MenuBarItemRecord(snapshot: .init(
            bundleIdentifier: "a",
            processID: 1,
            title: "One",
            description: nil,
            role: "AXMenuBarItem",
            subrole: nil,
            frame: CGRect(x: 20, y: 0, width: 20, height: 24),
            actionNames: ["AXPress"]
        ))
        let reader = StubMenuBarAXReader(result: .success([]))
        let service = MenuBarInventoryService(reader: reader)

        try service.press(record)

        XCTAssertEqual(reader.pressedIDs, [record.id])
    }
}
```

- [ ] **Step 2: Run the inventory tests and verify they fail**

Run: `swift test --filter MenuBarInventoryServiceTests`

Expected: build failure mentioning missing `MenuBarInventoryService`, `StubMenuBarAXReader`, and `MenuBarAXClientError`.

- [ ] **Step 3: Implement the AX reader and inventory service**

```swift
import AppKit
import ApplicationServices
import Foundation

enum MenuBarAXClientError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Accessibility permission is required."
        }
    }
}

protocol MenuBarAXReading {
    func fetchSnapshots() throws -> [MenuBarItemSnapshot]
    func pressItem(withID id: String) throws
    func startObserving(processes: Set<Int32>, onChange: @escaping () -> Void)
    func stopObserving()
}

final class StubMenuBarAXReader: MenuBarAXReading {
    var result: Result<[MenuBarItemSnapshot], Error>
    private(set) var pressedIDs: [String] = []

    init(result: Result<[MenuBarItemSnapshot], Error>) {
        self.result = result
    }

    func fetchSnapshots() throws -> [MenuBarItemSnapshot] {
        try result.get()
    }

    func pressItem(withID id: String) throws {
        pressedIDs.append(id)
    }

    func startObserving(processes: Set<Int32>, onChange: @escaping () -> Void) {}
    func stopObserving() {}
}

final class LiveMenuBarAXClient: MenuBarAXReading {
    private var observers: [Int32: AXObserver] = [:]
    private var elementsByID: [String: AXUIElement] = [:]

    func fetchSnapshots() throws -> [MenuBarItemSnapshot] {
        guard AXIsProcessTrusted() else { throw MenuBarAXClientError.permissionDenied }

        var snapshots: [MenuBarItemSnapshot] = []
        elementsByID = [:]

        for app in NSWorkspace.shared.runningApplications where app.processIdentifier > 0 {
            let application = AXUIElementCreateApplication(app.processIdentifier)
            var extrasMenuBarValue: CFTypeRef?
            let extrasAttribute = NSAccessibility.Attribute.extrasMenuBar.rawValue as CFString
            let extrasResult = AXUIElementCopyAttributeValue(application, extrasAttribute, &extrasMenuBarValue)
            guard extrasResult == .success, let extrasMenuBar = extrasMenuBarValue else { continue }

            var childrenValue: CFTypeRef?
            let childrenResult = AXUIElementCopyAttributeValue(extrasMenuBar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue)
            guard childrenResult == .success, let children = childrenValue as? [AXUIElement] else { continue }

            for child in children {
                let snapshot = MenuBarItemSnapshot(
                    bundleIdentifier: app.bundleIdentifier ?? "unknown.bundle",
                    processID: app.processIdentifier,
                    title: copyStringAttribute(kAXTitleAttribute, from: child),
                    description: copyStringAttribute(kAXDescriptionAttribute, from: child),
                    role: copyStringAttribute(kAXRoleAttribute, from: child),
                    subrole: copyStringAttribute(kAXSubroleAttribute, from: child),
                    frame: copyFrame(from: child),
                    actionNames: copyActionNames(from: child)
                )
                let record = MenuBarItemRecord(snapshot: snapshot)
                elementsByID[record.id] = child
                snapshots.append(snapshot)
            }
        }

        return snapshots
    }

    func pressItem(withID id: String) throws {
        guard let element = elementsByID[id] else { return }
        _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    func startObserving(processes: Set<Int32>, onChange: @escaping () -> Void) {
        stopObserving()

        for pid in processes {
            var observer: AXObserver?
            guard AXObserverCreate(pid, { _, _, _, refcon in
                let callback = Unmanaged<Box<() -> Void>>.fromOpaque(refcon!).takeUnretainedValue()
                callback.value()
            }, &observer) == .success, let observer else { continue }

            let callbackBox = Unmanaged.passRetained(Box(onChange))
            let appElement = AXUIElementCreateApplication(pid)
            _ = AXObserverAddNotification(observer, appElement, kAXCreatedNotification as CFString, callbackBox.toOpaque())
            _ = AXObserverAddNotification(observer, appElement, kAXMovedNotification as CFString, callbackBox.toOpaque())
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers[pid] = observer
        }
    }

    func stopObserving() {
        observers.removeAll()
    }

    private func copyStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func copyActionNames(from element: AXUIElement) -> [String] {
        var value: CFArray?
        guard AXUIElementCopyActionNames(element, &value) == .success, let array = value as? [String] else { return [] }
        return array
    }

    private func copyFrame(from element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionAX = positionValue as? AXValue,
              let sizeAX = sizeValue as? AXValue else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionAX, .cgPoint, &point)
        AXValueGetValue(sizeAX, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }
}

private final class Box<T> {
    let value: T
    init(_ value: T) { self.value = value }
}
```

```swift
import Foundation

@MainActor
final class MenuBarInventoryService: ObservableObject {
    @Published private(set) var records: [MenuBarItemRecord] = []
    @Published private(set) var lastRefreshError: String?

    private let reader: MenuBarAXReading

    init(reader: MenuBarAXReading = LiveMenuBarAXClient()) {
        self.reader = reader
    }

    func refresh() {
        do {
            let snapshots = try reader.fetchSnapshots()
            let records = snapshots
                .map(MenuBarItemRecord.init(snapshot:))
                .sorted { $0.frame.minX < $1.frame.minX }

            self.records = records
            self.lastRefreshError = nil
            reader.startObserving(processes: Set(records.map(\.processID))) { [weak self] in
                Task { @MainActor in
                    self?.refresh()
                }
            }
        } catch {
            self.lastRefreshError = error.localizedDescription
        }
    }

    func press(_ record: MenuBarItemRecord) throws {
        try reader.pressItem(withID: record.id)
    }
}
```

- [ ] **Step 4: Re-run the inventory tests and verify they pass**

Run: `swift test --filter MenuBarInventoryServiceTests`

Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit the inventory layer**

```bash
git add Sources/AwakeCup/MenuBarManager/MenuBarAXClient.swift Sources/AwakeCup/MenuBarManager/MenuBarInventoryService.swift Tests/AwakeCupTests/MenuBarManager/MenuBarInventoryServiceTests.swift
git commit -m "feat: add menu bar inventory service"
```

---

## Task 5: Add reveal-state logic and the overlay windows

**Files:**
- Create: `Sources/AwakeCup/MenuBarManager/MenuBarPresentationController.swift`
- Create: `Sources/AwakeCup/MenuBarManager/MenuBarOverlayController.swift`
- Test: `Tests/AwakeCupTests/MenuBarManager/MenuBarPresentationControllerTests.swift`

- [ ] **Step 1: Write the failing tests for preferred reveal mode, fallback, and auto-collapse**

```swift
import XCTest
@testable import AwakeCup

@MainActor
final class MenuBarPresentationControllerTests: XCTestCase {
    func testShowPreferredUsesExpandedStripWhenAvailable() {
        let controller = MenuBarPresentationController()
        controller.configuration.defaultRevealMode = .expandedStrip

        controller.showPreferred(canPresentExpandedStrip: true, now: .init(timeIntervalSince1970: 10))

        XCTAssertEqual(controller.state.activeSurface, .expandedStrip)
    }

    func testShowPreferredFallsBackToPanelWhenStripUnavailable() {
        let controller = MenuBarPresentationController()
        controller.configuration.defaultRevealMode = .expandedStrip

        controller.showPreferred(canPresentExpandedStrip: false, now: .init(timeIntervalSince1970: 10))

        XCTAssertEqual(controller.state.activeSurface, .panel)
    }

    func testTickAutoDismissesExpandedStripAfterDeadline() {
        let controller = MenuBarPresentationController()
        controller.configuration.defaultRevealMode = .expandedStrip
        controller.configuration.autoCollapseSeconds = 5
        controller.showPreferred(canPresentExpandedStrip: true, now: .init(timeIntervalSince1970: 10))

        controller.tick(now: .init(timeIntervalSince1970: 16))

        XCTAssertNil(controller.state.activeSurface)
    }
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run: `swift test --filter MenuBarPresentationControllerTests`

Expected: build failure mentioning missing `MenuBarPresentationController`.

- [ ] **Step 3: Implement the state controller and overlay windows**

```swift
import Foundation

enum HiddenItemsSurface: Equatable {
    case panel
    case expandedStrip
}

struct HiddenItemsPresentationState: Equatable {
    var activeSurface: HiddenItemsSurface?
    var autoCollapseDeadline: Date?
}

@MainActor
final class MenuBarPresentationController: ObservableObject {
    @Published private(set) var state = HiddenItemsPresentationState()
    var configuration = MenuBarLayoutConfiguration()

    func showPreferred(canPresentExpandedStrip: Bool, now: Date = Date()) {
        if configuration.defaultRevealMode == .expandedStrip, canPresentExpandedStrip {
            state.activeSurface = .expandedStrip
            state.autoCollapseDeadline = now.addingTimeInterval(configuration.autoCollapseSeconds)
        } else {
            state.activeSurface = .panel
            state.autoCollapseDeadline = nil
        }
    }

    func dismiss() {
        state.activeSurface = nil
        state.autoCollapseDeadline = nil
    }

    func tick(now: Date = Date()) {
        guard let deadline = state.autoCollapseDeadline, now >= deadline else { return }
        dismiss()
    }
}
```

```swift
import AppKit
import SwiftUI

@MainActor
protocol MenuBarOverlayControlling {
    func updateHiddenMask(for hiddenItems: [MenuBarItemRecord])
    func presentExpandedStrip(for hiddenItems: [MenuBarItemRecord])
    func dismissExpandedStrip()
    func hideHiddenMask()
}

@MainActor
final class MenuBarOverlayController: MenuBarOverlayControlling {
    private var maskWindow: NSWindow?
    private var stripWindow: NSPanel?

    func updateHiddenMask(for hiddenItems: [MenuBarItemRecord]) {
        guard let bounds = hiddenItems.boundingRect else {
            hideHiddenMask()
            return
        }

        let window = makeBorderlessWindow(frame: bounds, background: NSColor.windowBackgroundColor)
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
        maskWindow = window
    }

    func presentExpandedStrip(for hiddenItems: [MenuBarItemRecord]) {
        guard let frame = hiddenItems.boundingRect else { return }
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = NSHostingView(rootView:
            HStack(spacing: 8) {
                ForEach(hiddenItems) { item in
                    Text(item.displayName)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .padding(8)
        )
        panel.orderFrontRegardless()
        stripWindow = panel
    }

    func dismissExpandedStrip() {
        stripWindow?.orderOut(nil)
        stripWindow = nil
    }

    func hideHiddenMask() {
        maskWindow?.orderOut(nil)
        maskWindow = nil
    }

    private func makeBorderlessWindow(frame: CGRect, background: NSColor) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = background
        return window
    }
}

@MainActor
final class StubMenuBarOverlayController: MenuBarOverlayControlling {
    private(set) var lastHiddenMaskIDs: [String] = []
    private(set) var lastPresentedStripIDs: [String] = []
    private(set) var dismissExpandedStripCalls: Int = 0
    private(set) var hideHiddenMaskCalls: Int = 0

    func updateHiddenMask(for hiddenItems: [MenuBarItemRecord]) {
        lastHiddenMaskIDs = hiddenItems.map(\.id)
    }

    func presentExpandedStrip(for hiddenItems: [MenuBarItemRecord]) {
        lastPresentedStripIDs = hiddenItems.map(\.id)
    }

    func dismissExpandedStrip() {
        dismissExpandedStripCalls += 1
    }

    func hideHiddenMask() {
        hideHiddenMaskCalls += 1
    }
}

private extension Array where Element == MenuBarItemRecord {
    var boundingRect: CGRect? {
        guard let first = first else { return nil }
        return dropFirst().reduce(first.frame) { partial, next in
            partial.union(next.frame)
        }
    }
}
```

- [ ] **Step 4: Re-run the presentation tests and verify they pass**

Run: `swift test --filter MenuBarPresentationControllerTests`

Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit the reveal layer**

```bash
git add Sources/AwakeCup/MenuBarManager/MenuBarPresentationController.swift Sources/AwakeCup/MenuBarManager/MenuBarOverlayController.swift Tests/AwakeCupTests/MenuBarManager/MenuBarPresentationControllerTests.swift
git commit -m "feat: add hidden item presentation controllers"
```

---

## Task 6: Wire the manager into the menu bar panel and settings window

**Files:**
- Create: `Sources/AwakeCup/MenuBarManager/MenuBarManagerViewModel.swift`
- Create: `Sources/AwakeCup/MenuBarManager/MenuBarManagerSettingsView.swift`
- Create: `Sources/AwakeCup/MenuBarManager/MenuBarExtraContentView.swift`
- Test: `Tests/AwakeCupTests/MenuBarManager/MenuBarManagerViewModelTests.swift`
- Modify: `Sources/AwakeCup/AwakeCup.swift`

- [ ] **Step 1: Write the failing view-model tests for grouping items and permission fallback**

```swift
import CoreGraphics
import XCTest
@testable import AwakeCup

@MainActor
final class MenuBarManagerViewModelTests: XCTestCase {
    func testRefreshBuildsVisibleAndHiddenCollections() {
        let permission = AccessibilityPermissionController(checker: StubAccessibilityTrustChecker(responses: [true]))
        let inventory = MenuBarInventoryService(reader: StubMenuBarAXReader(result: .success([
            .init(bundleIdentifier: "a", processID: 1, title: "Visible", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 10, y: 0, width: 20, height: 24), actionNames: ["AXPress"]),
            .init(bundleIdentifier: "b", processID: 2, title: "Hidden", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 40, y: 0, width: 20, height: 24), actionNames: ["AXPress"]),
        ]))
        let layout = MenuBarLayoutStore(persistence: InMemoryLayoutPersistence())
        let presentation = MenuBarPresentationController()
        let overlay = StubMenuBarOverlayController()
        let viewModel = MenuBarManagerViewModel(permission: permission, inventory: inventory, layout: layout, presentation: presentation, overlay: overlay)

        layout.assign(.alwaysVisible, to: MenuBarItemRecord(snapshot: .init(bundleIdentifier: "a", processID: 1, title: "Visible", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 10, y: 0, width: 20, height: 24), actionNames: ["AXPress"])).id)
        layout.assign(.hidden, to: MenuBarItemRecord(snapshot: .init(bundleIdentifier: "b", processID: 2, title: "Hidden", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 40, y: 0, width: 20, height: 24), actionNames: ["AXPress"])).id)

        viewModel.refresh()

        XCTAssertEqual(viewModel.alwaysVisibleItems.map(\.displayName), ["Visible"])
        XCTAssertEqual(viewModel.hiddenItems.map(\.displayName), ["Hidden"])
    }

    func testRefreshStopsWhenPermissionIsDenied() {
        let permission = AccessibilityPermissionController(checker: StubAccessibilityTrustChecker(responses: [false]))
        let inventory = MenuBarInventoryService(reader: StubMenuBarAXReader(result: .success([])))
        let layout = MenuBarLayoutStore(persistence: InMemoryLayoutPersistence())
        let presentation = MenuBarPresentationController()
        let overlay = StubMenuBarOverlayController()
        let viewModel = MenuBarManagerViewModel(permission: permission, inventory: inventory, layout: layout, presentation: presentation, overlay: overlay)

        viewModel.refresh()

        XCTAssertFalse(viewModel.canManageItems)
        XCTAssertTrue(viewModel.hiddenItems.isEmpty)
    }

    func testShowHiddenItemsPresentsExpandedStripWhenPreferred() {
        let permission = AccessibilityPermissionController(checker: StubAccessibilityTrustChecker(responses: [true]))
        let inventory = MenuBarInventoryService(reader: StubMenuBarAXReader(result: .success([
            .init(bundleIdentifier: "b", processID: 2, title: "Hidden", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 40, y: 0, width: 20, height: 24), actionNames: ["AXPress"]),
        ]))
        let layout = MenuBarLayoutStore(persistence: InMemoryLayoutPersistence())
        layout.setDefaultRevealMode(.expandedStrip)
        let presentation = MenuBarPresentationController()
        let overlay = StubMenuBarOverlayController()
        let viewModel = MenuBarManagerViewModel(permission: permission, inventory: inventory, layout: layout, presentation: presentation, overlay: overlay)
        let hiddenRecord = MenuBarItemRecord(snapshot: .init(bundleIdentifier: "b", processID: 2, title: "Hidden", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 40, y: 0, width: 20, height: 24), actionNames: ["AXPress"]))
        layout.assign(.hidden, to: hiddenRecord.id)

        viewModel.refresh()
        viewModel.showHiddenItems()

        XCTAssertEqual(overlay.lastPresentedStripIDs, [hiddenRecord.id])
    }
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run: `swift test --filter MenuBarManagerViewModelTests`

Expected: build failure mentioning missing `MenuBarManagerViewModel`.

- [ ] **Step 3: Implement the view model**

```swift
import Foundation

@MainActor
final class MenuBarManagerViewModel: ObservableObject {
    @Published private(set) var canManageItems: Bool = false
    @Published private(set) var alwaysVisibleItems: [MenuBarItemRecord] = []
    @Published private(set) var hiddenItems: [MenuBarItemRecord] = []
    @Published private(set) var unmanagedItems: [MenuBarItemRecord] = []

    private let permission: AccessibilityPermissionController
    private let inventory: MenuBarInventoryService
    private let layout: MenuBarLayoutStore
    private let presentation: MenuBarPresentationController
    private let overlay: MenuBarOverlayControlling

    init(
        permission: AccessibilityPermissionController,
        inventory: MenuBarInventoryService,
        layout: MenuBarLayoutStore,
        presentation: MenuBarPresentationController,
        overlay: MenuBarOverlayControlling
    ) {
        self.permission = permission
        self.inventory = inventory
        self.layout = layout
        self.presentation = presentation
        self.overlay = overlay
    }

    func requestAccess() {
        permission.requestAccess()
        refresh()
    }

    func refresh() {
        permission.refresh()
        canManageItems = permission.canManageItems
        guard canManageItems else {
            alwaysVisibleItems = []
            hiddenItems = []
            unmanagedItems = []
            overlay.hideHiddenMask()
            overlay.dismissExpandedStrip()
            return
        }

        inventory.refresh()
        let manageableItems = inventory.records.filter {
            if case .manageable = $0.manageability { return true }
            return false
        }
        alwaysVisibleItems = layout.orderedItems(inventory: manageableItems, section: .alwaysVisible)
        hiddenItems = layout.orderedItems(inventory: manageableItems, section: .hidden)
        unmanagedItems = inventory.records.filter {
            if case .unmanaged = $0.manageability { return true }
            return false
        }
        overlay.updateHiddenMask(for: hiddenItems)
    }

    func move(_ item: MenuBarItemRecord, to section: MenuBarItemSection) {
        layout.assign(section, to: item.id)
        refresh()
    }

    func showHiddenItems() {
        presentation.configuration = layout.configuration
        presentation.showPreferred(canPresentExpandedStrip: !hiddenItems.isEmpty)
        if presentation.state.activeSurface == .expandedStrip {
            overlay.presentExpandedStrip(for: hiddenItems)
        } else {
            overlay.dismissExpandedStrip()
        }
    }

    func press(_ item: MenuBarItemRecord) {
        try? inventory.press(item)
    }

    func dismissHiddenItems() {
        presentation.dismiss()
        overlay.dismissExpandedStrip()
    }
}
```

- [ ] **Step 4: Implement the settings view and menu bar panel content**

```swift
import SwiftUI

struct MenuBarManagerSettingsView: View {
    @ObservedObject var viewModel: MenuBarManagerViewModel

    var body: some View {
        List {
            Section("Always Visible") {
                ForEach(viewModel.alwaysVisibleItems) { item in
                    row(for: item, target: .hidden, buttonTitle: "隐藏")
                }
            }

            Section("Hidden") {
                ForEach(viewModel.hiddenItems) { item in
                    row(for: item, target: .alwaysVisible, buttonTitle: "显示")
                }
            }

            if !viewModel.unmanagedItems.isEmpty {
                Section("Unsupported") {
                    ForEach(viewModel.unmanagedItems) { item in
                        VStack(alignment: .leading) {
                            Text(item.displayName)
                            if case let .unmanaged(reason) = item.manageability {
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }

    private func row(for item: MenuBarItemRecord, target: MenuBarItemSection, buttonTitle: String) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.displayName)
                Text(item.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(buttonTitle) {
                viewModel.move(item, to: target)
            }
        }
    }
}
```

```swift
import SwiftUI

struct MenuBarExtraContentView<Controls: View>: View {
    let controls: Controls
    @ObservedObject var manager: MenuBarManagerViewModel
    @Environment(\.openWindow) private var openWindow

    init(
        manager: MenuBarManagerViewModel,
        @ViewBuilder controls: () -> Controls
    ) {
        self.controls = controls()
        self._manager = ObservedObject(wrappedValue: manager)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                controls

                Divider()

                if manager.canManageItems {
                    Text("隐藏项：\(manager.hiddenItems.count)")
                        .font(.headline)
                    ForEach(manager.hiddenItems) { item in
                        Button(item.displayName) {
                            manager.press(item)
                        }
                    }
                    Button("显示隐藏项") {
                        manager.showHiddenItems()
                    }
                    Button("打开菜单栏管理") {
                        openWindow(id: "menu-bar-manager-settings")
                    }
                } else {
                    Text("需要辅助功能权限才能管理其他应用图标。")
                        .font(.callout)
                    Button("请求权限") {
                        manager.requestAccess()
                    }
                }
            }
            .padding(12)
            .frame(minWidth: 320)
        }
        .onAppear {
            manager.refresh()
        }
    }
}
```

- [ ] **Step 5: Update the app scene wiring in `Sources/AwakeCup/AwakeCup.swift`**

First extract the current `MenuBarExtra` content block into `private var currentControls: some View` in the same file without changing any caffeine behavior. Then wire the app scenes like this:

```swift
@StateObject private var permissionController = AccessibilityPermissionController()
@StateObject private var inventoryService = MenuBarInventoryService()
@StateObject private var layoutStore = MenuBarLayoutStore()
@StateObject private var presentationController = MenuBarPresentationController()
private let overlayController: MenuBarOverlayControlling
@StateObject private var menuBarManager: MenuBarManagerViewModel

init() {
    let permission = AccessibilityPermissionController()
    let inventory = MenuBarInventoryService()
    let layout = MenuBarLayoutStore()
    let presentation = MenuBarPresentationController()
    let overlay = MenuBarOverlayController()
    _permissionController = StateObject(wrappedValue: permission)
    _inventoryService = StateObject(wrappedValue: inventory)
    _layoutStore = StateObject(wrappedValue: layout)
    _presentationController = StateObject(wrappedValue: presentation)
    self.overlayController = overlay
    _menuBarManager = StateObject(
        wrappedValue: MenuBarManagerViewModel(
            permission: permission,
            inventory: inventory,
            layout: layout,
            presentation: presentation,
            overlay: overlay
        )
    )
}

private var currentControls: some View {
    VStack(alignment: .leading, spacing: 10) {
        HStack {
            Text(modeStatusText(system: caffeine.isSystemActive, display: caffeine.isDisplayActive))
            Spacer()
            if caffeine.isSystemActive || caffeine.isDisplayActive {
                Button("停止") { caffeine.deactivate() }
                    .keyboardShortcut("s")
            }
        }

        if (caffeine.isSystemActive || caffeine.isDisplayActive), let until = caffeine.activeUntil {
            Text("将在 \(until.formatted(date: .omitted, time: .shortened)) 停止")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Divider()

        Toggle("开机自启动", isOn: $launchAtLogin)
            .disabled(isApplyingLaunchAtLogin)
            .onAppear {
                launchAtLogin = LaunchAtLogin.currentEnabledState()
            }
            .onChange(of: launchAtLogin) { newValue in
                guard !isApplyingLaunchAtLogin else { return }
                isApplyingLaunchAtLogin = true
                Task { @MainActor in
                    defer { isApplyingLaunchAtLogin = false }
                    do {
                        try LaunchAtLogin.setEnabled(newValue)
                    } catch {
                        launchAtLogin.toggle()
                    }
                }
            }

        Text("保持目标")
            .font(.caption)
            .foregroundStyle(.secondary)

        Picker("保持目标", selection: $selectedMode) {
            ForEach(CaffeineManager.Mode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)

        Text("开始保持唤醒")
            .font(.caption)
            .foregroundStyle(.secondary)

        HStack(spacing: 4) {
            TextField("30", text: $customDurationValue)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
                .onChange(of: customDurationValue) { newValue in
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered != newValue {
                        customDurationValue = filtered
                    }
                }

            Picker("", selection: $customDurationUnit) {
                ForEach(CustomDurationEntry.Unit.allCases) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 60)

            Button("开始") {
                activateCustom()
            }
            .disabled(!canActivateCustom)
            .buttonStyle(.bordered)
        }

        if !history.isEmpty {
            HStack(spacing: 2) {
                Text("最近：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(history) { entry in
                    Button(entry.displayTitle) {
                        activateFromHistory(entry)
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                    if entry.id != history.last?.id {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        Divider()

        ForEach(DurationOption.allCases) { option in
            Button(option.title) {
                if let seconds = option.seconds {
                    caffeine.activate(mode: selectedMode, for: seconds)
                } else {
                    caffeine.activateIndefinitely(mode: selectedMode)
                }
            }
            .disabled((caffeine.isSystemActive || caffeine.isDisplayActive) && option == .indefinite && caffeine.activeUntil == nil && caffeine.activeMode == selectedMode)
        }

        Divider()

        Button("退出") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

var body: some Scene {
    MenuBarExtra {
        MenuBarExtraContentView(manager: menuBarManager) {
            currentControls
        }
    } label: {
        Image(nsImage: MenuBarIcon.makeImage(
            isSystemActive: caffeine.isSystemActive,
            isDisplayActive: caffeine.isDisplayActive,
            activeMode: caffeine.activeMode,
            activationStartTime: caffeine.activationStartTime,
            activeUntil: caffeine.activeUntil
        ))
        .help(menuBarHelpText(
            system: caffeine.isSystemActive,
            display: caffeine.isDisplayActive,
            activeUntil: caffeine.activeUntil
        ))
    }
    .menuBarExtraStyle(.window)

    Window("菜单栏管理", id: "menu-bar-manager-settings") {
        MenuBarManagerSettingsView(viewModel: menuBarManager)
    }
}
```

- [ ] **Step 6: Re-run the focused view-model tests and the full suite**

Run: `swift test --filter MenuBarManagerViewModelTests`

Expected: `Executed 3 tests, with 0 failures`.

Run: `swift test`

Expected: all existing and new tests pass with `0 failures`.

- [ ] **Step 7: Commit the integrated UI**

```bash
git add Sources/AwakeCup/AwakeCup.swift Sources/AwakeCup/MenuBarManager/MenuBarManagerViewModel.swift Sources/AwakeCup/MenuBarManager/MenuBarManagerSettingsView.swift Sources/AwakeCup/MenuBarManager/MenuBarExtraContentView.swift Tests/AwakeCupTests/MenuBarManager/MenuBarManagerViewModelTests.swift
git commit -m "feat: wire menu bar manager UI"
```

---

## Task 7: Run full verification and do the manual menu-bar-manager pass

**Files:**
- Modify only if verification reveals issues.

- [ ] **Step 1: Run the full automated test suite**

Run: `swift test`

Expected: all tests pass with `0 failures`.

- [ ] **Step 2: Build the app in debug mode**

Run: `swift build`

Expected: `Build complete!`

- [ ] **Step 3: Launch the app locally**

Run: `swift run`

Expected: the AwakeCup menu bar icon appears; on first use of the manager the app prompts for Accessibility permission.

- [ ] **Step 4: Manually verify the five required user flows**

1. Start with Accessibility denied and confirm the menu bar panel shows a permission CTA instead of partial inventory data.
2. Grant Accessibility and reopen the panel; confirm the settings window lists discovered items under `Always Visible` and `Hidden`.
3. Move one manageable item to `Hidden` and confirm it disappears from the normal visible region under the mask overlay.
4. Trigger `显示隐藏项` and confirm the item becomes reachable through the temporary expanded strip and then auto-collapses.
5. Confirm the existing AwakeCup caffeine controls still activate and deactivate sleep prevention exactly as before.

- [ ] **Step 5: If verification required changes, commit the fixes**

```bash
git add -A
git commit -m "fix: address menu bar manager verification issues"
```
