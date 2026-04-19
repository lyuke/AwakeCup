import Combine
import Foundation

@MainActor
final class MenuBarInventoryService: ObservableObject {
    @Published private(set) var records: [MenuBarItemRecord] = []
    @Published private(set) var lastRefreshError: String?

    private let reader: MenuBarAXReading
    private var observedProcessIDs: Set<Int32> = []

    init(reader: MenuBarAXReading = MenuBarAXClient()) {
        self.reader = reader
    }

    func refresh() {
        do {
            let snapshots = try reader.fetchSnapshots()
            let refreshedRecords = snapshots
                .map(MenuBarItemRecord.init(snapshot:))
                .sorted(by: MenuBarItemRecord.sortsBeforeInDisplayOrder)

            records = refreshedRecords
            lastRefreshError = nil

            let processIDs = Set(refreshedRecords.map(\.processID))
            if processIDs.isEmpty {
                stopObservingIfNeeded()
            } else if observedProcessIDs != processIDs {
                stopObservingIfNeeded()
                observedProcessIDs = reader.startObserving(processIDs: processIDs) { [weak self] in
                    Task { @MainActor in
                        self?.refresh()
                    }
                }
            }
        } catch {
            records = []
            stopObservingIfNeeded()
            lastRefreshError = error.localizedDescription
        }
    }

    func reset() {
        records = []
        lastRefreshError = nil
        stopObservingIfNeeded()
    }

    func press(_ record: MenuBarItemRecord) throws {
        try reader.press(record.id)
    }

    private func stopObservingIfNeeded() {
        guard !observedProcessIDs.isEmpty else {
            return
        }
        reader.stopObserving()
        observedProcessIDs = []
    }
}
