import AppKit
import SwiftUI

let menuBarManagerSettingsWindowID = "menu-bar-manager-settings"

struct MenuBarExtraContentView<Controls: View>: View {
    @ObservedObject var manager: MenuBarManagerViewModel
    @Environment(\.openWindow) private var openWindow

    private let controls: Controls

    init(
        manager: MenuBarManagerViewModel,
        @ViewBuilder controls: () -> Controls
    ) {
        _manager = ObservedObject(wrappedValue: manager)
        self.controls = controls()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                controls
                Divider()
                managerSection
            }
            .padding(12)
            .frame(minWidth: 320, alignment: .leading)
        }
        .onAppear {
            manager.refresh()
        }
    }

    @ViewBuilder
    private var managerSection: some View {
        if manager.canManageItems {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("隐藏项")
                        .font(.headline)
                    Spacer()
                    Text("\(manager.hiddenItems.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if manager.hiddenItems.isEmpty {
                    Text("当前没有隐藏项。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(manager.hiddenItems) { item in
                        Button(item.displayName) {
                            manager.press(item)
                        }
                    }
                }

                Button("显示隐藏项") {
                    manager.showHiddenItems()
                }
                .disabled(manager.hiddenItems.isEmpty)

                Button("菜单栏管理") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: menuBarManagerSettingsWindowID)
                }

                if let inventoryErrorMessage = manager.inventoryErrorMessage {
                    Text(inventoryErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("菜单栏管理需要辅助功能权限。")
                    .font(.callout)
                Button("请求权限") {
                    manager.requestAccess()
                }
                Button("菜单栏管理") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: menuBarManagerSettingsWindowID)
                }
            }
        }
    }
}
