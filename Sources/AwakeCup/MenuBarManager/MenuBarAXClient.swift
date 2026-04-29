@preconcurrency import ApplicationServices
import AppKit
import Foundation

enum MenuBarAXClientError: LocalizedError, Equatable {
    case permissionDenied
    case itemNotFound(String)
    case pressFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Accessibility permission is required."
        case .itemNotFound(let runtimeID):
            return "Menu bar item \(runtimeID) is no longer available."
        case .pressFailed(let runtimeID):
            return "Unable to press menu bar item \(runtimeID)."
        }
    }
}

enum MenuBarAXObservationRegistrationPolicy {
    static func shouldTrackObserver(notificationResults: [AXError]) -> Bool {
        notificationResults.contains(.success)
    }
}

@MainActor
protocol MenuBarAXReading: AnyObject {
    func fetchSnapshots() throws -> [MenuBarItemSnapshot]
    func press(_ runtimeID: String) throws
    func startObserving(processIDs: Set<Int32>, onChange: @escaping () -> Void) -> Set<Int32>
    func stopObserving()
}

@MainActor
final class MenuBarAXClient: MenuBarAXReading {
    private struct Observation {
        let observer: AXObserver
        let source: CFRunLoopSource
        let callbackToken: Unmanaged<ObservationCallbackBox>
    }

    private static let extrasMenuBarAttribute = "AXExtrasMenuBar" as CFString
    private static let observerCallback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        let box = Unmanaged<ObservationCallbackBox>.fromOpaque(refcon).takeUnretainedValue()
        box.invoke()
    }

    private var observations: [Int32: Observation] = [:]
    private var elementsByRuntimeID: [String: AXUIElement] = [:]

    nonisolated static func identityHint(identifier: String?, help: String?, siblingIndex: Int?) -> String? {
        if let identifier = normalizedIdentityAttribute(identifier) {
            return "identifier:\(identifier)"
        }
        if let help = normalizedIdentityAttribute(help) {
            return "help:\(help)"
        }
        if let siblingIndex {
            return "index:\(siblingIndex)"
        }
        return nil
    }

    func fetchSnapshots() throws -> [MenuBarItemSnapshot] {
        guard AXIsProcessTrusted() else {
            throw MenuBarAXClientError.permissionDenied
        }

        elementsByRuntimeID.removeAll(keepingCapacity: true)

        var snapshots: [MenuBarItemSnapshot] = []
        for application in NSWorkspace.shared.runningApplications where application.processIdentifier > 0 {
            let appElement = AXUIElementCreateApplication(application.processIdentifier)

            var extrasMenuBarValue: CFTypeRef?
            let extrasResult = AXUIElementCopyAttributeValue(
                appElement,
                Self.extrasMenuBarAttribute,
                &extrasMenuBarValue
            )
            guard extrasResult == .success, let extrasMenuBarValue else {
                continue
            }
            guard CFGetTypeID(extrasMenuBarValue) == AXUIElementGetTypeID() else {
                continue
            }
            let extrasMenuBar = unsafeDowncast(extrasMenuBarValue, to: AXUIElement.self)

            var childrenValue: CFTypeRef?
            let childrenResult = AXUIElementCopyAttributeValue(
                extrasMenuBar,
                kAXChildrenAttribute as CFString,
                &childrenValue
            )
            guard childrenResult == .success, let children = childrenValue as? [AXUIElement] else {
                continue
            }

            let shouldIncludeSiblingIndex = children.count > 1
            for (index, child) in children.enumerated() {
                let snapshot = MenuBarItemSnapshot(
                    bundleIdentifier: application.bundleIdentifier ?? "unknown.bundle",
                    processID: application.processIdentifier,
                    title: copyStringAttribute(kAXTitleAttribute as CFString, from: child),
                    description: copyStringAttribute(kAXDescriptionAttribute as CFString, from: child),
                    role: copyStringAttribute(kAXRoleAttribute as CFString, from: child),
                    subrole: copyStringAttribute(kAXSubroleAttribute as CFString, from: child),
                    frame: copyFrame(from: child),
                    actionNames: copyActionNames(from: child),
                    identityHint: Self.identityHint(
                        identifier: copyStringAttribute(kAXIdentifierAttribute as CFString, from: child),
                        help: copyStringAttribute(kAXHelpAttribute as CFString, from: child),
                        siblingIndex: shouldIncludeSiblingIndex ? index + 1 : nil
                    )
                )
                let record = MenuBarItemRecord(snapshot: snapshot)
                elementsByRuntimeID[record.id] = child
                snapshots.append(snapshot)
            }
        }

        return snapshots
    }

    func press(_ runtimeID: String) throws {
        guard let element = elementsByRuntimeID[runtimeID] else {
            throw MenuBarAXClientError.itemNotFound(runtimeID)
        }

        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard result == .success else {
            throw MenuBarAXClientError.pressFailed(runtimeID)
        }
    }

    func startObserving(processIDs: Set<Int32>, onChange: @escaping () -> Void) -> Set<Int32> {
        stopObserving()

        guard !processIDs.isEmpty else {
            return []
        }

        var observedProcessIDs: Set<Int32> = []
        for processID in processIDs {
            var observer: AXObserver?
            let callbackToken = Unmanaged.passRetained(ObservationCallbackBox(onChange))
            let createResult = AXObserverCreate(processID, Self.observerCallback, &observer)
            guard createResult == .success, let observer else {
                callbackToken.release()
                continue
            }

            let runLoopSource = AXObserverGetRunLoopSource(observer)
            let applicationElement = AXUIElementCreateApplication(processID)
            let notificationResults = [
                AXObserverAddNotification(
                    observer,
                    applicationElement,
                    kAXCreatedNotification as CFString,
                    callbackToken.toOpaque()
                ),
                AXObserverAddNotification(
                    observer,
                    applicationElement,
                    kAXMovedNotification as CFString,
                    callbackToken.toOpaque()
                ),
                AXObserverAddNotification(
                    observer,
                    applicationElement,
                    kAXUIElementDestroyedNotification as CFString,
                    callbackToken.toOpaque()
                ),
            ]
            guard MenuBarAXObservationRegistrationPolicy.shouldTrackObserver(
                notificationResults: notificationResults
            ) else {
                callbackToken.release()
                continue
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, CFRunLoopMode.defaultMode)
            observations[processID] = Observation(
                observer: observer,
                source: runLoopSource,
                callbackToken: callbackToken
            )
            observedProcessIDs.insert(processID)
        }

        return observedProcessIDs
    }

    func stopObserving() {
        guard !observations.isEmpty else {
            return
        }

        for observation in observations.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), observation.source, CFRunLoopMode.defaultMode)
            observation.callbackToken.release()
        }
        observations.removeAll(keepingCapacity: true)
    }

    private func copyStringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func copyActionNames(from element: AXUIElement) -> [String] {
        var value: CFArray?
        guard AXUIElementCopyActionNames(element, &value) == .success, let actions = value as? [String] else {
            return []
        }
        return actions
    }

    private func copyFrame(from element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }
        let positionAXValue = unsafeDowncast(positionValue, to: AXValue.self)
        let sizeAXValue = unsafeDowncast(sizeValue, to: AXValue.self)
        guard AXValueGetType(positionAXValue) == .cgPoint,
              AXValueGetType(sizeAXValue) == .cgSize else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &point),
              AXValueGetValue(sizeAXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: point, size: size)
    }

    private nonisolated static func normalizedIdentityAttribute(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private final class ObservationCallbackBox {
    private let callback: () -> Void

    init(_ callback: @escaping () -> Void) {
        self.callback = callback
    }

    func invoke() {
        callback()
    }
}
