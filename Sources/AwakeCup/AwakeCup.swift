import AppKit
import Darwin
import IOKit.pwr_mgt
import ServiceManagement
import SwiftUI

private enum LaunchAtLogin {
    private static let bundleID = "com.awakecup.app"
    private static let launchAgentLabel = "com.awakecup.app.launchatlogin"

    private static var launchAgentsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    private static var launchAgentPlistURL: URL {
        launchAgentsDir.appendingPathComponent("\(launchAgentLabel).plist")
    }

    private static var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private static var programArguments: [String] {
        if isRunningFromAppBundle {
            return ["/usr/bin/open", "-a", Bundle.main.bundlePath]
        }
        // 开发态（swift run）兜底：直接跑当前可执行文件路径。
        return [CommandLine.arguments.first ?? "/usr/bin/true"]
    }

    static func currentEnabledState() -> Bool {
        if #available(macOS 13.0, *), isRunningFromAppBundle {
            return SMAppService.mainApp.status == .enabled
        }
        return FileManager.default.fileExists(atPath: launchAgentPlistURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        // 优先走系统“登录项”（macOS 13+），对用户更直观（系统设置里可见）。
        if #available(macOS 13.0, *), isRunningFromAppBundle {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                return
            } catch {
                // 某些未签名/未从 .app 运行的场景可能失败，兜底到 LaunchAgent。
            }
        }

        if enabled {
            try enableViaLaunchAgent()
        } else {
            try disableViaLaunchAgent()
        }
    }

    private static func enableViaLaunchAgent() throws {
        try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "ProgramArguments": programArguments,
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: launchAgentPlistURL, options: .atomic)

        let uid = String(getuid())
        let domainTarget = "gui/\(uid)"

        // 若已加载，先卸载再加载，避免 bootstrap 报错。
        _ = try? runLaunchctl(["bootout", "\(domainTarget)/\(launchAgentLabel)"])
        _ = try runLaunchctl(["bootstrap", domainTarget, launchAgentPlistURL.path])
    }

    private static func disableViaLaunchAgent() throws {
        let uid = String(getuid())
        let domainTarget = "gui/\(uid)"
        _ = try? runLaunchctl(["bootout", "\(domainTarget)/\(launchAgentLabel)"])
        try? FileManager.default.removeItem(at: launchAgentPlistURL)
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw NSError(
                domain: bundleID,
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: (err.isEmpty ? out : err).trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }
        return out
    }
}

@MainActor
final class CaffeineManager: ObservableObject {
    static let shared = CaffeineManager()

    enum Mode: String, CaseIterable, Identifiable {
        case systemAndDisplay
        case systemOnly
        case displayOnly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .systemAndDisplay: return "系统 + 屏幕"
            case .systemOnly: return "仅系统"
            case .displayOnly: return "仅屏幕（防锁屏）"
            }
        }

        var needsSystem: Bool {
            switch self {
            case .systemAndDisplay, .systemOnly: return true
            case .displayOnly: return false
            }
        }

        var needsDisplay: Bool {
            switch self {
            case .systemAndDisplay, .displayOnly: return true
            case .systemOnly: return false
            }
        }
    }

    @Published private(set) var isSystemActive: Bool = false
    @Published private(set) var isDisplayActive: Bool = false
    @Published private(set) var activeMode: Mode? = nil
    @Published private(set) var activeUntil: Date? = nil

    private var systemAssertionID: IOPMAssertionID = 0
    private var displayAssertionID: IOPMAssertionID = 0
    private var stopTimer: Timer? = nil

    private init() {}

    func activateIndefinitely() {
        activate(mode: .systemAndDisplay, until: nil)
    }

    func activate(for seconds: TimeInterval) {
        activate(mode: .systemAndDisplay, until: Date().addingTimeInterval(seconds))
    }

    func activateIndefinitely(mode: Mode) {
        activate(mode: mode, until: nil)
    }

    func activate(mode: Mode, for seconds: TimeInterval) {
        activate(mode: mode, until: Date().addingTimeInterval(seconds))
    }

    func deactivate() {
        stopTimer?.invalidate()
        stopTimer = nil
        activeUntil = nil

        if isSystemActive {
            IOPMAssertionRelease(systemAssertionID)
            systemAssertionID = 0
            isSystemActive = false
        }

        if isDisplayActive {
            IOPMAssertionRelease(displayAssertionID)
            displayAssertionID = 0
            isDisplayActive = false
        }

        activeMode = nil
    }

    private func activate(mode: Mode, until date: Date?) {
        stopTimer?.invalidate()
        stopTimer = nil

        // 先释放不需要的旧 assertion，避免重复持有。
        if isSystemActive && !mode.needsSystem {
            IOPMAssertionRelease(systemAssertionID)
            systemAssertionID = 0
            isSystemActive = false
        }
        if isDisplayActive && !mode.needsDisplay {
            IOPMAssertionRelease(displayAssertionID)
            displayAssertionID = 0
            isDisplayActive = false
        }

        if mode.needsSystem && !isSystemActive {
        let reason = "AwakeCup: Prevent idle system sleep" as CFString
            let type = kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
            let result = IOPMAssertionCreateWithName(
                type,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &systemAssertionID
            )
            if result == kIOReturnSuccess {
                isSystemActive = true
            } else {
                systemAssertionID = 0
                isSystemActive = false
            }
        }

        if mode.needsDisplay && !isDisplayActive {
            let reason = "AwakeCup: Prevent idle display sleep" as CFString
            let type = kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
            let result = IOPMAssertionCreateWithName(
                type,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &displayAssertionID
            )
            if result == kIOReturnSuccess {
                isDisplayActive = true
            } else {
                displayAssertionID = 0
                isDisplayActive = false
            }
        }

        activeMode = (isSystemActive || isDisplayActive) ? mode : nil
        activeUntil = date

        if let date {
            let interval = max(0, date.timeIntervalSinceNow)
            stopTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.deactivate()
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 作为菜单栏应用运行：不显示 Dock 图标，不显示主窗口。
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        CaffeineManager.shared.deactivate()
    }
}

private enum DurationOption: Identifiable, CaseIterable {
    case fiveMinutes
    case oneHour
    case twoHours
    case indefinite

    var id: String { title }

    var title: String {
        switch self {
        case .fiveMinutes: return "5 分钟"
        case .oneHour: return "1 小时"
        case .twoHours: return "2 小时"
        case .indefinite: return "一直保持"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .fiveMinutes: return 5 * 60
        case .oneHour: return 60 * 60
        case .twoHours: return 2 * 60 * 60
        case .indefinite: return nil
        }
    }
}

private func modeStatusText(system: Bool, display: Bool) -> String {
    switch (system, display) {
    case (true, true): return "系统不休眠 + 屏幕常亮"
    case (true, false): return "仅系统不休眠"
    case (false, true): return "仅屏幕常亮（防锁屏）"
    case (false, false): return "未保持唤醒"
    }
}

@main
struct AwakeCupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var caffeine = CaffeineManager.shared

    @State private var selectedMode: CaffeineManager.Mode = .systemAndDisplay
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @State private var isApplyingLaunchAtLogin: Bool = false

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(modeStatusText(system: caffeine.isSystemActive, display: caffeine.isDisplayActive))
                    Spacer()
                    if caffeine.isSystemActive || caffeine.isDisplayActive {
                        Button("停止") { caffeine.deactivate() }
                            .keyboardShortcut("s")
                    }
                }

                if (caffeine.isSystemActive || caffeine.isDisplayActive), let until = caffeine.activeUntil {
                    Text("将在 \(until.formatted(date: .omitted, time: .shortened)) 停止")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Toggle("开机自启动", isOn: $launchAtLogin)
                    .disabled(isApplyingLaunchAtLogin)
                    .onAppear {
                        // 以实际系统状态为准（避免 UserDefaults 与系统不同步）。
                        launchAtLogin = LaunchAtLogin.currentEnabledState()
                    }
                    .onChange(of: launchAtLogin) { newValue in
                        guard !isApplyingLaunchAtLogin else { return }
                        isApplyingLaunchAtLogin = true
                        Task { @MainActor in
                            defer { isApplyingLaunchAtLogin = false }
                            do {
                                try LaunchAtLogin.setEnabled(newValue)
                            } catch {
                                // 回滚 UI 状态
                                launchAtLogin.toggle()

                                let alert = NSAlert()
                                alert.alertStyle = .warning
                                alert.messageText = "无法设置开机自启动"
                                alert.informativeText = error.localizedDescription
                                alert.addButton(withTitle: "好")
                                alert.runModal()
                            }
                        }
                    }

                Text("保持目标")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("保持目标", selection: $selectedMode) {
                    ForEach(CaffeineManager.Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Text("开始保持唤醒")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(DurationOption.allCases) { option in
                    Button(option.title) {
                        if let seconds = option.seconds {
                            caffeine.activate(mode: selectedMode, for: seconds)
                        } else {
                            caffeine.activateIndefinitely(mode: selectedMode)
                        }
                    }
                    .disabled((caffeine.isSystemActive || caffeine.isDisplayActive) && option == .indefinite && caffeine.activeUntil == nil && caffeine.activeMode == selectedMode)
                }

                Divider()

                Button("退出") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(12)
            .frame(minWidth: 220)
        } label: {
            Image(systemName: (caffeine.isSystemActive || caffeine.isDisplayActive) ? "cup.and.saucer.fill" : "cup.and.saucer")
        }
    }
}
