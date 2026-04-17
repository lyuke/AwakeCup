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
