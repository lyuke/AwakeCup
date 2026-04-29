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
    private var autoCollapseTimer: Timer?

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
            scheduleAutoCollapse(after: configuration.autoCollapseAfter)
        default:
            activate(.panel, autoCollapseDeadline: nil)
            cancelAutoCollapse()
        }
    }

    func dismiss() {
        cancelAutoCollapse()
        state = MenuBarPresentationState()
    }

    func tick(now: Date = Date()) {
        guard let deadline = state.autoCollapseDeadline, now >= deadline else {
            return
        }
        dismiss()
    }

    private func activate(_ surface: MenuBarPresentationSurface, autoCollapseDeadline: Date?) {
        state = MenuBarPresentationState(
            activeSurface: surface,
            autoCollapseDeadline: autoCollapseDeadline
        )
    }

    private func scheduleAutoCollapse(after interval: TimeInterval) {
        cancelAutoCollapse()
        autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: max(0, interval), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func cancelAutoCollapse() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(configuration) else {
            return
        }
        persistence.saveData(data, forKey: storageKey)
    }
}
