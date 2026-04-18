import Combine
import Foundation

enum HiddenItemRevealMode: String, Codable, Equatable {
    case panel
    case expandedStrip
}

enum MenuBarPresentationSurface: Equatable {
    case panel
    case expandedStrip
}

struct MenuBarPresentationState: Equatable {
    var activeSurface: MenuBarPresentationSurface? = nil
    var autoCollapseDeadline: Date? = nil
}

struct MenuBarPresentationConfiguration: Codable, Equatable {
    var preferredRevealMode: HiddenItemRevealMode = .panel
    var autoCollapseAfter: TimeInterval = 5
}

protocol MenuBarPresentationPersisting {
    func loadData(forKey key: String) -> Data?
    func saveData(_ data: Data, forKey key: String)
}

struct UserDefaultsMenuBarPresentationPersistence: MenuBarPresentationPersisting {
    let defaults: UserDefaults = .standard

    func loadData(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func saveData(_ data: Data, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

@MainActor
final class MenuBarPresentationController: ObservableObject {
    @Published private(set) var state = MenuBarPresentationState()
    @Published var configuration: MenuBarPresentationConfiguration {
        didSet {
            persist()
        }
    }

    private let persistence: MenuBarPresentationPersisting
    private let storageKey = "menuBarManagerPresentation"

    init(persistence: MenuBarPresentationPersisting = UserDefaultsMenuBarPresentationPersistence()) {
        self.persistence = persistence
        if let data = persistence.loadData(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(MenuBarPresentationConfiguration.self, from: data) {
            configuration = decoded
        } else {
            configuration = MenuBarPresentationConfiguration()
        }
    }

    func showPreferred(canPresentExpandedStrip: Bool, now: Date = Date()) {
        switch configuration.preferredRevealMode {
        case .expandedStrip where canPresentExpandedStrip:
            activate(.expandedStrip, autoCollapseDeadline: now.addingTimeInterval(configuration.autoCollapseAfter))
        default:
            activate(.panel, autoCollapseDeadline: nil)
        }
    }

    func dismiss() {
        state.activeSurface = nil
        state.autoCollapseDeadline = nil
    }

    func tick(now: Date = Date()) {
        guard let deadline = state.autoCollapseDeadline, now >= deadline else {
            return
        }
        dismiss()
    }

    private func activate(_ surface: MenuBarPresentationSurface, autoCollapseDeadline: Date?) {
        state.activeSurface = surface
        state.autoCollapseDeadline = autoCollapseDeadline
    }

    private func persist() {
        let data = try! JSONEncoder().encode(configuration)
        persistence.saveData(data, forKey: storageKey)
    }
}
