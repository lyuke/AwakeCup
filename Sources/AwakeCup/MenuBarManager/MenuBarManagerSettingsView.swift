import SwiftUI

struct MenuBarManagerSettingsView: View {
    @ObservedObject var viewModel: MenuBarManagerViewModel

    var body: some View {
        List {
            revealModeSection
            contentSection
        }
        .frame(minWidth: 460, minHeight: 420)
        .navigationTitle("菜单栏管理")
        .onAppear {
            viewModel.refresh()
        }
    }

    private var revealModeSection: some View {
        Section("显示方式") {
            Picker("隐藏项显示方式", selection: revealModeBinding) {
                ForEach(HiddenItemRevealMode.allCases, id: \.self) { mode in
                    Text(mode.displayTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text("面板更稳定，展开条更贴近原始菜单栏位置。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        if viewModel.canManageItems {
            Section("快捷操作") {
                Button("隐藏其他顶部图标") {
                    viewModel.hideOtherVisibleItems()
                }
                .disabled(!viewModel.canHideOtherVisibleItems)

                Text("将除 AwakeCup 外当前顶部图标批量移到隐藏项。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("始终显示") {
                if viewModel.alwaysVisibleItems.isEmpty {
                    emptyState("当前没有固定显示的项目。")
                } else {
                    ForEach(viewModel.alwaysVisibleItems) { item in
                        ManagedItemRow(item: item, buttonTitle: "隐藏") {
                            viewModel.move(item, to: .hidden)
                        }
                    }
                }
            }

            Section("隐藏项") {
                if viewModel.hiddenItems.isEmpty {
                    emptyState("当前没有隐藏项。")
                } else {
                    ForEach(viewModel.hiddenItems) { item in
                        ManagedItemRow(item: item, buttonTitle: "显示") {
                            viewModel.move(item, to: .alwaysVisible)
                        }
                    }
                }
            }

            if !viewModel.unmanagedItems.isEmpty {
                Section("无法控制") {
                    ForEach(viewModel.unmanagedItems) { item in
                        UnmanagedItemRow(item: item)
                    }
                }
            }

            if let inventoryErrorMessage = viewModel.inventoryErrorMessage {
                Section("状态") {
                    Text(inventoryErrorMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Section("权限") {
                Text("需要辅助功能权限才能整理其他应用的菜单栏图标。")
                    .font(.callout)
                Button("请求权限") {
                    viewModel.requestAccess()
                }
            }
        }
    }

    private var revealModeBinding: Binding<HiddenItemRevealMode> {
        Binding(
            get: { viewModel.preferredRevealMode },
            set: { viewModel.setPreferredRevealMode($0) }
        )
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

private struct ManagedItemRow: View {
    let item: MenuBarItemRecord
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                    if item.isUnmanaged {
                        Label("不可点击", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}

private struct UnmanagedItemRow: View {
    let item: MenuBarItemRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.displayName)
            Text(item.bundleIdentifier)
                .font(.caption)
                .foregroundStyle(.secondary)
            if case let .unmanaged(reason) = item.manageability {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private extension HiddenItemRevealMode {
    static let allCases: [HiddenItemRevealMode] = [.panel, .expandedStrip]

    var displayTitle: String {
        switch self {
        case .panel:
            return "面板"
        case .expandedStrip:
            return "展开条"
        }
    }
}
