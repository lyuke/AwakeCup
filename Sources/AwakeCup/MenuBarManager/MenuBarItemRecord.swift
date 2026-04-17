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
        let normalizedSubrole = OptionalIdentityString(snapshot.subrole?.nonEmpty)
        let normalizedIdentityHint = OptionalIdentityString(snapshot.identityHint?.nonEmpty)

        let manageability: MenuBarItemManageability = snapshot.actionNames.contains("AXPress")
            ? .manageable
            : .unmanaged(reason: "Missing AXPress action")

        let coarseX = Int(frame.minX.rounded())
        let coarseY = Int(frame.minY.rounded())
        let coarseWidth = Int(frame.width.rounded())
        let coarseHeight = Int(frame.height.rounded())

        self.persistentID = Self.encodeIdentityComponents(
            PersistentIdentityPayload(
                version: 1,
                bundleIdentifier: snapshot.bundleIdentifier,
                role: role,
                subrole: normalizedSubrole,
                identityHint: normalizedIdentityHint
            )
        )

        self.runtimeID = Self.encodeIdentityComponents(
            RuntimeIdentityPayload(
                version: 1,
                persistentID: persistentID,
                displayName: displayName,
                actionNames: sortedActionNames,
                geometry: GeometryIdentity(
                    x: coarseX,
                    y: coarseY,
                    width: coarseWidth,
                    height: coarseHeight
                )
            )
        )

        self.bundleIdentifier = snapshot.bundleIdentifier
        self.processID = snapshot.processID
        self.displayName = displayName
        self.axRole = role
        self.axSubrole = snapshot.subrole
        self.frame = frame
        self.actionNames = sortedActionNames
        self.manageability = manageability
    }

    private static func encodeIdentityComponents<T: Encodable>(_ value: T) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct OptionalIdentityString: Encodable, Equatable {
    let value: String?

    init(_ value: String?) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        if let value {
            try container.encode("some")
            try container.encode(value)
        } else {
            try container.encode("none")
        }
    }
}

private struct PersistentIdentityPayload: Encodable, Equatable {
    let version: Int
    let bundleIdentifier: String
    let role: String
    let subrole: OptionalIdentityString
    let identityHint: OptionalIdentityString

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(version)
        try container.encode(bundleIdentifier)
        try container.encode(role)
        try container.encode(subrole)
        try container.encode(identityHint)
    }
}

private struct GeometryIdentity: Encodable, Equatable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
        try container.encode(width)
        try container.encode(height)
    }
}

private struct RuntimeIdentityPayload: Encodable, Equatable {
    let version: Int
    let persistentID: String
    let displayName: String
    let actionNames: [String]
    let geometry: GeometryIdentity

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(version)
        try container.encode(persistentID)
        try container.encode(displayName)
        try container.encode(actionNames)
        try container.encode(geometry)
    }
}
