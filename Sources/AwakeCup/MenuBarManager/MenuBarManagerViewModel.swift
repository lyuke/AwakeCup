import Foundation

@MainActor
final class MenuBarManagerViewModel: ObservableObject {
    @Published private(set) var permissionState: AccessibilityPermissionController.State
    @Published private(set) var canManageItems: Bool
    @Published private(set) var preferredRevealMode: HiddenItemRevealMode
    @Published private(set) var inventoryErrorMessage: String?
    @Published private(set) var alwaysVisibleItems: [MenuBarItemRecord] = []
    @Published private(set) var hiddenItems: [MenuBarItemRecord] = []
    @Published private(set) var unmanagedItems: [MenuBarItemRecord] = []

    private let permission: AccessibilityPermissionController
    private let inventory: MenuBarInventoryService
    private let layout: MenuBarLayoutStore
    private let presentation: MenuBarPresentationController
    private let overlay: MenuBarOverlayControlling

    init(
        permission: AccessibilityPermissionController,
        inventory: MenuBarInventoryService,
        layout: MenuBarLayoutStore,
        presentation: MenuBarPresentationController,
        overlay: MenuBarOverlayControlling
    ) {
        self.permission = permission
        self.inventory = inventory
        self.layout = layout
        self.presentation = presentation
        self.overlay = overlay
        permissionState = permission.state
        canManageItems = permission.canManageItems
        preferredRevealMode = presentation.configuration.preferredRevealMode
        inventoryErrorMessage = inventory.lastRefreshError
    }

    func refresh() {
        permission.refresh()
        permissionState = permission.state
        canManageItems = permission.canManageItems
        preferredRevealMode = presentation.configuration.preferredRevealMode

        guard canManageItems else {
            inventoryErrorMessage = nil
            alwaysVisibleItems = []
            hiddenItems = []
            unmanagedItems = []
            presentation.dismiss()
            overlay.hideHiddenMask()
            overlay.dismissExpandedStrip()
            return
        }

        inventory.refresh()
        inventoryErrorMessage = inventory.lastRefreshError

        let manageableItems = inventory.records.filter(\.isManageable)
        alwaysVisibleItems = layout.orderedItems(inventory: manageableItems, section: .alwaysVisible)
        hiddenItems = layout.orderedItems(inventory: manageableItems, section: .hidden)
        unmanagedItems = inventory.records.filter(\.isUnmanaged)

        overlay.updateHiddenMask(for: hiddenItems)
        syncExpandedStripVisibility()
    }

    func requestAccess() {
        permission.requestAccess()
        refresh()
    }

    func move(_ item: MenuBarItemRecord, to section: MenuBarItemSection) {
        layout.assign(section, toPersistentID: item.persistentID)
        refresh()
    }

    func setPreferredRevealMode(_ mode: HiddenItemRevealMode) {
        guard presentation.configuration.preferredRevealMode != mode else {
            preferredRevealMode = mode
            return
        }
        presentation.configuration.preferredRevealMode = mode
        preferredRevealMode = mode
        syncExpandedStripVisibility()
    }

    func showHiddenItems() {
        presentation.showPreferred(canPresentExpandedStrip: !hiddenItems.isEmpty)
        syncExpandedStripVisibility()
    }

    func dismissHiddenItems() {
        presentation.dismiss()
        overlay.dismissExpandedStrip()
    }

    func press(_ item: MenuBarItemRecord) {
        try? inventory.press(item)
    }

    private func syncExpandedStripVisibility() {
        guard presentation.state.activeSurface == .expandedStrip, !hiddenItems.isEmpty else {
            if presentation.state.activeSurface == .expandedStrip, hiddenItems.isEmpty {
                presentation.dismiss()
            }
            overlay.dismissExpandedStrip()
            return
        }

        overlay.presentExpandedStrip(for: hiddenItems)
    }
}

private extension MenuBarItemRecord {
    var isManageable: Bool {
        if case .manageable = manageability {
            return true
        }
        return false
    }

    var isUnmanaged: Bool {
        if case .unmanaged = manageability {
            return true
        }
        return false
    }
}
