import Foundation
import SwiftUI

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
