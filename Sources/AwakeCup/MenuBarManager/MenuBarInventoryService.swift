import Combine
import Foundation

@MainActor
final class MenuBarInventoryService: ObservableObject {
    @Published private(set) var records: [MenuBarItemRecord] = []
    @Published private(set) var lastRefreshError: String?

    private let reader: MenuBarAXReading

    init(reader: MenuBarAXReading = MenuBarAXClient()) {
        self.reader = reader
    }

    func refresh() {
        do {
            let snapshots = try reader.fetchSnapshots()
            let refreshedRecords = snapshots
                .map(MenuBarItemRecord.init(snapshot:))
                .sorted { $0.frame.minX < $1.frame.minX }

            records = refreshedRecords
            lastRefreshError = nil

            let processIDs = Set(refreshedRecords.map(\.processID))
            if processIDs.isEmpty {
                reader.stopObserving()
            } else {
                reader.startObserving(processIDs: processIDs) { [weak self] in
                    Task { @MainActor in
                        self?.refresh()
                    }
                }
            }
        } catch {
            records = []
            reader.stopObserving()
            lastRefreshError = error.localizedDescription
        }
    }

    func press(_ record: MenuBarItemRecord) throws {
        try reader.press(record.id)
    }
}
