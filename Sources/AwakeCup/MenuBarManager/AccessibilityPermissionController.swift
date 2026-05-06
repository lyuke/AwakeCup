@preconcurrency import ApplicationServices
import Foundation
import Combine

protocol AccessibilityTrustChecking {
    func isTrusted(prompt: Bool) -> Bool
}

struct LiveAccessibilityTrustChecker: AccessibilityTrustChecking {
    func isTrusted(prompt: Bool) -> Bool {
        let options: CFDictionary? = prompt
            ? [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            : nil
        return AXIsProcessTrustedWithOptions(options)
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
        state = checker.isTrusted(prompt: false) ? .granted : .denied
    }

    func refresh() {
        state = checker.isTrusted(prompt: false) ? .granted : .denied
    }

    func requestAccess() {
        state = checker.isTrusted(prompt: true) ? .granted : .denied
    }
}
