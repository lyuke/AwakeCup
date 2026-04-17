import Foundation
import SwiftUI

struct MenuBarLayoutConfiguration: Codable, Equatable {
    var assignments: [String: MenuBarItemSection] = [:]
    var orderBySection: [MenuBarItemSection: [String]] = [:]
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

    func assign(_ section: MenuBarItemSection, toPersistentID persistentID: String) {
        configuration.assignments[persistentID] = section
        persist()
    }

    func updateOrder(for section: MenuBarItemSection, persistentIDs: [String]) {
        configuration.orderBySection[section] = persistentIDs
        persist()
    }

    func section(for item: MenuBarItemRecord) -> MenuBarItemSection {
        configuration.assignments[item.persistentID] ?? .alwaysVisible
    }

    func orderedItems(inventory: [MenuBarItemRecord], section: MenuBarItemSection) -> [MenuBarItemRecord] {
        let records = inventory.filter { self.section(for: $0) == section }
        let order = configuration.orderBySection[section] ?? []

        return records.sorted { left, right in
            let leftIndex = order.firstIndex(of: left.persistentID) ?? .max
            let rightIndex = order.firstIndex(of: right.persistentID) ?? .max
            if leftIndex != rightIndex { return leftIndex < rightIndex }
            return left.frame.minX < right.frame.minX
        }
    }

    private func persist() {
        let data = try! JSONEncoder().encode(configuration)
        persistence.saveData(data, forKey: storageKey)
    }
}
