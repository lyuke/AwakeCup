import Combine
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
    private let currentAppBundleIdentifier: String?
    private var cancellables: Set<AnyCancellable> = []

    init(
        permission: AccessibilityPermissionController,
        inventory: MenuBarInventoryService,
        layout: MenuBarLayoutStore,
        presentation: MenuBarPresentationController,
        overlay: MenuBarOverlayControlling,
        currentAppBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.permission = permission
        self.inventory = inventory
        self.layout = layout
        self.presentation = presentation
        self.overlay = overlay
        self.currentAppBundleIdentifier = currentAppBundleIdentifier
        permissionState = permission.state
        canManageItems = permission.canManageItems
        preferredRevealMode = presentation.configuration.preferredRevealMode
        inventoryErrorMessage = inventory.lastRefreshError

        presentation.$state
            .dropFirst()
            .sink { [weak self] state in
                self?.syncExpandedStripVisibility(using: state)
            }
            .store(in: &cancellables)
    }

    func refresh() {
        permission.refresh()
        permissionState = permission.state
        canManageItems = permission.canManageItems
        preferredRevealMode = presentation.configuration.preferredRevealMode

        guard canManageItems else {
            inventory.reset()
            inventoryErrorMessage = inventory.lastRefreshError
            alwaysVisibleItems = []
            hiddenItems = []
            unmanagedItems = []
            presentation.dismiss()
            overlay.hideHiddenMask()
            return
        }

        inventory.refresh()
        inventoryErrorMessage = inventory.lastRefreshError

        let manageableItems = inventory.records.filter(\.isManageable)
        alwaysVisibleItems = layout.orderedItems(inventory: manageableItems, section: .alwaysVisible)
        hiddenItems = layout.orderedItems(inventory: manageableItems, section: .hidden)
        unmanagedItems = inventory.records.filter(\.isUnmanaged)

        if hiddenItems.allSatisfy(\.hasKnownFrame) {
            overlay.updateHiddenMask(for: hiddenItems)
        } else {
            overlay.hideHiddenMask()
        }
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

    func hideOtherVisibleItems() {
        let itemsToHide = alwaysVisibleItems.filter { item in
            item.bundleIdentifier != currentAppBundleIdentifier
        }
        guard !itemsToHide.isEmpty else {
            return
        }

        layout.assign(.hidden, toPersistentIDs: itemsToHide.map(\.persistentID))
        refresh()
    }

    func setPreferredRevealMode(_ mode: HiddenItemRevealMode) {
        guard presentation.configuration.preferredRevealMode != mode else {
            preferredRevealMode = mode
            return
        }
        presentation.configuration.preferredRevealMode = mode
        preferredRevealMode = mode
        if mode == .panel, presentation.state.activeSurface == .expandedStrip {
            presentation.dismiss()
            return
        }
        syncExpandedStripVisibility()
    }

    func showHiddenItems() {
        presentation.showPreferred(canPresentExpandedStrip: hiddenItems.allSatisfy(\.hasKnownFrame) && !hiddenItems.isEmpty)
        syncExpandedStripVisibility()
    }

    func dismissHiddenItems() {
        presentation.dismiss()
    }

    func press(_ item: MenuBarItemRecord) {
        do {
            try inventory.press(item)
            inventoryErrorMessage = nil
        } catch {
            inventoryErrorMessage = error.localizedDescription
        }
    }

    var canHideOtherVisibleItems: Bool {
        alwaysVisibleItems.contains { item in
            item.bundleIdentifier != currentAppBundleIdentifier
        }
    }

    private func syncExpandedStripVisibility(using state: MenuBarPresentationState? = nil) {
        let presentationState = state ?? presentation.state

        guard presentationState.activeSurface == .expandedStrip, !hiddenItems.isEmpty else {
            if presentationState.activeSurface == .expandedStrip, hiddenItems.isEmpty {
                presentation.dismiss()
            }
            overlay.dismissExpandedStrip()
            return
        }

        overlay.presentExpandedStrip(for: hiddenItems) { [weak self] item in
            self?.pressFromExpandedStrip(item)
        }
    }

    private func pressFromExpandedStrip(_ item: MenuBarItemRecord) {
        press(item)
        if inventoryErrorMessage != nil {
            presentation.dismiss()
        }
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
