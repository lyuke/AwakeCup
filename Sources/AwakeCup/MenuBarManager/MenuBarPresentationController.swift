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

struct MenuBarPresentationConfiguration: Equatable {
    var preferredRevealMode: HiddenItemRevealMode = .panel
    var autoCollapseAfter: TimeInterval = 5
}

@MainActor
final class MenuBarPresentationController: ObservableObject {
    @Published private(set) var state = MenuBarPresentationState()

    var configuration = MenuBarPresentationConfiguration()

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
}
