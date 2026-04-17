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
}

struct MenuBarItemRecord: Identifiable, Codable, Equatable {
    let id: String
    let bundleIdentifier: String
    let processID: Int32
    let displayName: String
    let axRole: String
    let axSubrole: String?
    let frame: CGRect
    let actionNames: [String]
    let manageability: MenuBarItemManageability

    init(snapshot: MenuBarItemSnapshot) {
        let role = snapshot.role ?? "AXUnknown"
        let frame = snapshot.frame ?? .zero
        let sortedActionNames = snapshot.actionNames.sorted()
        let displayName = snapshot.title?.nonEmpty
            ?? snapshot.description?.nonEmpty
            ?? snapshot.bundleIdentifier

        let manageability: MenuBarItemManageability = snapshot.actionNames.contains("AXPress")
            ? .manageable
            : .unmanaged(reason: "Missing AXPress action")

        let coarseX = Int(frame.minX.rounded())
        let coarseWidth = Int(frame.width.rounded())

        self.id = [
            snapshot.bundleIdentifier,
            role,
            snapshot.subrole ?? "-",
            displayName,
            sortedActionNames.joined(separator: ","),
            "\(coarseX)",
            "\(coarseWidth)",
        ].joined(separator: "|")
        self.bundleIdentifier = snapshot.bundleIdentifier
        self.processID = snapshot.processID
        self.displayName = displayName
        self.axRole = role
        self.axSubrole = snapshot.subrole
        self.frame = frame
        self.actionNames = sortedActionNames
        self.manageability = manageability
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
