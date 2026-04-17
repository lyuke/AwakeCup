import CoreGraphics
import Foundation

enum MenuBarItemSection: String, Codable, CaseIterable, Equatable {
    case alwaysVisible
    case hidden
}

enum MenuBarItemManageability: Codable, Equatable {
    case manageable
    case unmanaged(reason: String)
}

struct MenuBarItemSnapshot: Equatable {
    let bundleIdentifier: String
    let processID: Int32
    let title: String?
    let description: String?
    let role: String?
    let subrole: String?
    let frame: CGRect?
    let actionNames: [String]
    let identityHint: String?

    init(
        bundleIdentifier: String,
        processID: Int32,
        title: String?,
        description: String?,
        role: String?,
        subrole: String?,
        frame: CGRect?,
        actionNames: [String],
        identityHint: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.processID = processID
        self.title = title
        self.description = description
        self.role = role
        self.subrole = subrole
        self.frame = frame
        self.actionNames = actionNames
        self.identityHint = identityHint
    }
}

struct MenuBarItemRecord: Identifiable, Codable, Equatable {
    let persistentID: String
    let runtimeID: String
    let bundleIdentifier: String
    let processID: Int32
    let displayName: String
    let axRole: String
    let axSubrole: String?
    let frame: CGRect
    let actionNames: [String]
    let manageability: MenuBarItemManageability

    var id: String { runtimeID }

    init(snapshot: MenuBarItemSnapshot) {
        let role = snapshot.role ?? "AXUnknown"
        let frame = snapshot.frame ?? .zero
        let sortedActionNames = snapshot.actionNames.sorted()
        let displayName = snapshot.title?.nonEmpty
            ?? snapshot.description?.nonEmpty
            ?? snapshot.bundleIdentifier
        let normalizedIdentityHint = snapshot.identityHint?.nonEmpty

        let manageability: MenuBarItemManageability = snapshot.actionNames.contains("AXPress")
            ? .manageable
            : .unmanaged(reason: "Missing AXPress action")

        let coarseX = Int(frame.minX.rounded())
        let coarseY = Int(frame.minY.rounded())
        let coarseWidth = Int(frame.width.rounded())
        let coarseHeight = Int(frame.height.rounded())

        self.persistentID = Self.encodeIdentityComponents([
            snapshot.bundleIdentifier,
            role,
            snapshot.subrole ?? "-",
            normalizedIdentityHint ?? "-",
        ])

        self.runtimeID = Self.encodeIdentityComponents([
            persistentID,
            displayName,
            sortedActionNames.joined(separator: ","),
            "\(coarseX)",
            "\(coarseY)",
            "\(coarseWidth)",
            "\(coarseHeight)",
        ])

        self.bundleIdentifier = snapshot.bundleIdentifier
        self.processID = snapshot.processID
        self.displayName = displayName
        self.axRole = role
        self.axSubrole = snapshot.subrole
        self.frame = frame
        self.actionNames = sortedActionNames
        self.manageability = manageability
    }

    private static func encodeIdentityComponents(_ components: [String]) -> String {
        let data = (try? JSONEncoder().encode(components)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
