import CoreGraphics
import XCTest
@testable import AwakeCup

@MainActor
final class MenuBarInventoryServiceTests: XCTestCase {
    func testRefreshSortsRecordsByMenuBarPositionAndClearsPreviousError() {
        let reader = StubMenuBarAXReader()
        reader.fetchResult = .failure(MenuBarAXClientError.permissionDenied)
        let service = MenuBarInventoryService(reader: reader)

        service.refresh()

        XCTAssertEqual(service.lastRefreshError, "Accessibility permission is required.")

        reader.fetchResult = .success([
            .init(bundleIdentifier: "b", processID: 2, title: "Two", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 80, y: 0, width: 20, height: 24), actionNames: ["AXPress"]),
            .init(bundleIdentifier: "a", processID: 1, title: "One", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 20, y: 0, width: 20, height: 24), actionNames: ["AXPress"]),
        ])

        service.refresh()

        XCTAssertEqual(service.records.map(\.displayName), ["One", "Two"])
        XCTAssertEqual(service.records.map(\.frame.minX), [20, 80])
        XCTAssertNil(service.lastRefreshError)
    }

    func testRefreshStoresReadableErrorWhenReaderFails() {
        let reader = StubMenuBarAXReader()
        reader.fetchResult = .failure(MenuBarAXClientError.permissionDenied)
        let service = MenuBarInventoryService(reader: reader)

        service.refresh()

        XCTAssertEqual(service.lastRefreshError, "Accessibility permission is required.")
        XCTAssertTrue(service.records.isEmpty)
    }

    func testRefreshClearsStaleRecordsAndStopsObservingWhenAPreviouslySuccessfulRefreshFails() {
        let reader = StubMenuBarAXReader()
        reader.fetchResult = .success([
            .init(bundleIdentifier: "a", processID: 1, title: "One", description: nil, role: "AXMenuBarItem", subrole: nil, frame: CGRect(x: 20, y: 0, width: 20, height: 24), actionNames: ["AXPress"])
        ])
        let service = MenuBarInventoryService(reader: reader)

        service.refresh()

        XCTAssertEqual(service.records.map(\.displayName), ["One"])
        XCTAssertEqual(reader.startObservationCalls.count, 1)
        XCTAssertEqual(reader.stopObservationCalls, 0)

        reader.fetchResult = .failure(MenuBarAXClientError.permissionDenied)

        service.refresh()

        XCTAssertEqual(service.records, [])
        XCTAssertEqual(service.lastRefreshError, "Accessibility permission is required.")
        XCTAssertEqual(reader.startObservationCalls.count, 1)
        XCTAssertEqual(reader.stopObservationCalls, 1)
    }

    func testPressDelegatesToReaderUsingRuntimeIdentity() throws {
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
        let reader = StubMenuBarAXReader()
        let service = MenuBarInventoryService(reader: reader)

        try service.press(record)

        XCTAssertEqual(reader.pressedIDs, [record.id])
    }
}

@MainActor
private final class StubMenuBarAXReader: MenuBarAXReading {
    var fetchResult: Result<[MenuBarItemSnapshot], Error> = .success([])
    private(set) var pressedIDs: [String] = []
    private(set) var startObservationCalls: [(processIDs: Set<Int32>, onChange: () -> Void)] = []
    private(set) var stopObservationCalls = 0

    func fetchSnapshots() throws -> [MenuBarItemSnapshot] {
        try fetchResult.get()
    }

    func press(_ runtimeID: String) throws {
        pressedIDs.append(runtimeID)
    }

    func startObserving(processIDs: Set<Int32>, onChange: @escaping () -> Void) {
        startObservationCalls.append((processIDs: processIDs, onChange: onChange))
    }

    func stopObserving() {
        stopObservationCalls += 1
    }
}
