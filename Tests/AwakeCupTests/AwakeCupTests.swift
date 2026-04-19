import XCTest
@testable import AwakeCup

final class AwakeCupTests: XCTestCase {
    func testLaunchAgentControllerRemovesPlistWhenBootstrapFails() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let launchAgentsDir = tempDirectory.appendingPathComponent("LaunchAgents", isDirectory: true)
        let plistURL = launchAgentsDir.appendingPathComponent("com.awakecup.test.plist")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        var commands: [[String]] = []
        let controller = LaunchAtLoginLaunchAgentController(
            label: "com.awakecup.test",
            launchAgentsDir: launchAgentsDir,
            launchAgentPlistURL: plistURL,
            programArguments: ["/usr/bin/true"],
            currentUserID: { 501 },
            runLaunchctl: { arguments in
                commands.append(arguments)
                if arguments.first == "bootstrap" {
                    throw NSError(domain: "LaunchAgentTest", code: 1)
                }
                return ""
            }
        )

        XCTAssertThrowsError(try controller.enable())
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertEqual(commands.map(\.first), ["bootout", "bootstrap"])
    }

    func testLaunchAgentControllerKeepsPlistWhenBootstrapSucceeds() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let launchAgentsDir = tempDirectory.appendingPathComponent("LaunchAgents", isDirectory: true)
        let plistURL = launchAgentsDir.appendingPathComponent("com.awakecup.test.plist")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let controller = LaunchAtLoginLaunchAgentController(
            label: "com.awakecup.test",
            launchAgentsDir: launchAgentsDir,
            launchAgentPlistURL: plistURL,
            programArguments: ["/usr/bin/true"],
            currentUserID: { 501 },
            runLaunchctl: { _ in "" }
        )

        try controller.enable()

        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
    }

    // MARK: - LaunchAtLogin Toggle Flow Tests

    func testLaunchAtLoginSyncSuppressesNextProgrammaticChange() {
        var coordinator = LaunchAtLoginToggleCoordinator()

        coordinator.prepareForProgrammaticValueChange(to: true)

        XCTAssertEqual(coordinator.displayedValue, true)
        XCTAssertFalse(coordinator.beginUserInitiatedApplyIfNeeded())
        XCTAssertFalse(coordinator.isApplying)
    }

    func testLaunchAtLoginBeginUserApplySetsApplyingState() {
        var coordinator = LaunchAtLoginToggleCoordinator()
        coordinator.displayedValue = false
        coordinator.displayedValue = true

        XCTAssertTrue(coordinator.beginUserInitiatedApplyIfNeeded())
        XCTAssertTrue(coordinator.isApplying)
    }

    func testLaunchAtLoginFailureRevertsValueAndSuppressesRollbackChange() {
        var coordinator = LaunchAtLoginToggleCoordinator()
        coordinator.displayedValue = false
        coordinator.displayedValue = true
        XCTAssertTrue(coordinator.beginUserInitiatedApplyIfNeeded())

        coordinator.finishApply(success: false, attemptedValue: true)

        XCTAssertEqual(coordinator.displayedValue, false)
        XCTAssertFalse(coordinator.isApplying)
        XCTAssertFalse(coordinator.beginUserInitiatedApplyIfNeeded())
    }

    func testLaunchAtLoginEnabledStateUsesLaunchAgentFallbackWhenAppServiceIsDisabled() {
        let status = LaunchAtLoginEnabledState.from(
            isRunningFromAppBundle: true,
            appServiceEnabled: false,
            launchAgentExists: true
        )

        XCTAssertTrue(status)
    }

    func testLaunchAtLoginEnabledStateUsesAppServiceWhenAvailable() {
        let status = LaunchAtLoginEnabledState.from(
            isRunningFromAppBundle: true,
            appServiceEnabled: true,
            launchAgentExists: false
        )

        XCTAssertTrue(status)
    }

    func testLaunchAtLoginEnabledStateUsesLaunchAgentOutsideAppBundle() {
        let status = LaunchAtLoginEnabledState.from(
            isRunningFromAppBundle: false,
            appServiceEnabled: false,
            launchAgentExists: true
        )

        XCTAssertTrue(status)
    }

    func testLaunchAtLoginFallbackCleanupRunsWhenDisablingFromAppBundle() {
        XCTAssertTrue(
            LaunchAtLoginFallbackCleanupPolicy.shouldDisableLaunchAgentAfterAppServiceSuccess(
                isRunningFromAppBundle: true,
                requestedEnabled: false
            )
        )
    }

    func testLaunchAtLoginFallbackCleanupRunsWhenEnablingFromAppBundle() {
        XCTAssertTrue(
            LaunchAtLoginFallbackCleanupPolicy.shouldDisableLaunchAgentAfterAppServiceSuccess(
                isRunningFromAppBundle: true,
                requestedEnabled: true
            )
        )
    }

    func testLaunchAtLoginFallbackCleanupDoesNotRunOutsideAppBundle() {
        XCTAssertFalse(
            LaunchAtLoginFallbackCleanupPolicy.shouldDisableLaunchAgentAfterAppServiceSuccess(
                isRunningFromAppBundle: false,
                requestedEnabled: true
            )
        )
    }

    // MARK: - Activation Timeline Tests

    func testActivationTimelineClearsCountdownMetadataWhenNothingIsActive() {
        let now = Date(timeIntervalSince1970: 100)
        let requestedEnd = now.addingTimeInterval(3600)

        let timeline = ActivationTimeline.from(
            isActive: false,
            requestedEnd: requestedEnd,
            now: now
        )

        XCTAssertNil(timeline.activationStartTime)
        XCTAssertNil(timeline.activeUntil)
    }

    func testActivationTimelineStartsCountdownWhenActivationSucceeds() {
        let now = Date(timeIntervalSince1970: 100)
        let requestedEnd = now.addingTimeInterval(3600)

        let timeline = ActivationTimeline.from(
            isActive: true,
            requestedEnd: requestedEnd,
            now: now
        )

        XCTAssertEqual(timeline.activationStartTime, now)
        XCTAssertEqual(timeline.activeUntil, requestedEnd)
    }

    func testActivationTimelineOmitsCountdownForIndefiniteActivation() {
        let now = Date(timeIntervalSince1970: 100)

        let timeline = ActivationTimeline.from(
            isActive: true,
            requestedEnd: nil,
            now: now
        )

        XCTAssertNil(timeline.activationStartTime)
        XCTAssertNil(timeline.activeUntil)
    }

    // MARK: - Resolved Wake Mode Tests

    func testResolvedWakeModeUsesSystemOnlyForPartialActivation() {
        let mode = ResolvedWakeMode.from(
            isSystemActive: true,
            isDisplayActive: false
        )

        XCTAssertEqual(mode, .systemOnly)
    }

    func testResolvedWakeModeUsesDisplayOnlyForPartialActivation() {
        let mode = ResolvedWakeMode.from(
            isSystemActive: false,
            isDisplayActive: true
        )

        XCTAssertEqual(mode, .displayOnly)
    }

    func testResolvedWakeModeUsesCombinedModeWhenBothAssertionsAreActive() {
        let mode = ResolvedWakeMode.from(
            isSystemActive: true,
            isDisplayActive: true
        )

        XCTAssertEqual(mode, .systemAndDisplay)
    }

    // MARK: - MenuBarIconState Tests

    func testIconStateInactive() {
        XCTAssertFalse(MenuBarIcon.isActive(isSystemActive: false, isDisplayActive: false))
    }

    func testIconStateSystemActiveOnly() {
        XCTAssertTrue(MenuBarIcon.isActive(isSystemActive: true, isDisplayActive: false))
    }

    func testIconStateDisplayActiveOnly() {
        XCTAssertTrue(MenuBarIcon.isActive(isSystemActive: false, isDisplayActive: true))
    }

    func testIconStateBothActive() {
        XCTAssertTrue(MenuBarIcon.isActive(isSystemActive: true, isDisplayActive: true))
    }

    // MARK: - MenuBarIconState Model Tests

    func testStateFromInactive() {
        let state = MenuBarIconState.from(
            isSystemActive: false,
            isDisplayActive: false,
            activeMode: nil,
            activationStartTime: nil,
            activeUntil: nil
        )
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.mode)
        XCTAssertNil(state.countdownProgress)
        XCTAssertFalse(state.hasCountdown)
    }

    func testStateFromSystemOnly() {
        let state = MenuBarIconState.from(
            isSystemActive: true,
            isDisplayActive: false,
            activeMode: .systemOnly,
            activationStartTime: nil,
            activeUntil: nil
        )
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.mode, .systemOnly)
        XCTAssertFalse(state.hasCountdown)
    }

    func testStateFromUsesActualFlagsWhenRequestedModeOverstatesSystemOnly() {
        let state = MenuBarIconState.from(
            isSystemActive: true,
            isDisplayActive: false,
            activeMode: .systemAndDisplay,
            activationStartTime: nil,
            activeUntil: nil
        )

        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.mode, .systemOnly)
    }

    func testStateFromDisplayOnly() {
        let state = MenuBarIconState.from(
            isSystemActive: false,
            isDisplayActive: true,
            activeMode: .displayOnly,
            activationStartTime: nil,
            activeUntil: nil
        )
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.mode, .displayOnly)
    }

    func testStateFromUsesActualFlagsWhenRequestedModeOverstatesDisplayOnly() {
        let state = MenuBarIconState.from(
            isSystemActive: false,
            isDisplayActive: true,
            activeMode: .systemAndDisplay,
            activationStartTime: nil,
            activeUntil: nil
        )

        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.mode, .displayOnly)
    }

    func testStateFromSystemAndDisplay() {
        let state = MenuBarIconState.from(
            isSystemActive: true,
            isDisplayActive: true,
            activeMode: .systemAndDisplay,
            activationStartTime: nil,
            activeUntil: nil
        )
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.mode, .systemAndDisplay)
    }

    func testBadgeStyleSystemOnly() {
        XCTAssertEqual(MenuBarIconState.Mode.systemOnly.badgeStyle, .verticalBar)
    }

    func testBadgeStyleDisplayOnly() {
        XCTAssertEqual(MenuBarIconState.Mode.displayOnly.badgeStyle, .dot)
    }

    func testBadgeStyleSystemAndDisplay() {
        XCTAssertEqual(MenuBarIconState.Mode.systemAndDisplay.badgeStyle, .doubleBar)
    }

    // MARK: - Countdown Progress Tests

    func testCountdownProgressNoCountdownWhenInactive() {
        let state = MenuBarIconState(
            isActive: false,
            mode: nil,
            activationStartTime: nil,
            activeUntil: nil
        )
        XCTAssertNil(state.countdownProgress)
        XCTAssertFalse(state.hasCountdown)
    }

    func testCountdownProgressNoCountdownWhenIndefinite() {
        let state = MenuBarIconState(
            isActive: true,
            mode: .systemAndDisplay,
            activationStartTime: Date(),
            activeUntil: nil
        )
        XCTAssertNil(state.countdownProgress)
        XCTAssertFalse(state.hasCountdown)
    }

    func testCountdownProgressFullAtStart() {
        let start = Date()
        let end = start.addingTimeInterval(3600)  // 1 hour
        let state = MenuBarIconState(
            isActive: true,
            mode: .systemOnly,
            activationStartTime: start,
            activeUntil: end
        )
        let progress = state.countdownProgress
        XCTAssertNotNil(progress)
        XCTAssertGreaterThan(progress!, 0.99)
        XCTAssertLessThanOrEqual(progress!, 1.0)
    }

    func testCountdownProgressHalfway() {
        let start = Date().addingTimeInterval(-1800)  // 30 min ago
        let end = Date().addingTimeInterval(1800)   // 30 min from now
        let state = MenuBarIconState(
            isActive: true,
            mode: .displayOnly,
            activationStartTime: start,
            activeUntil: end
        )
        let progress = state.countdownProgress
        XCTAssertNotNil(progress)
        XCTAssertGreaterThan(progress!, 0.45)
        XCTAssertLessThan(progress!, 0.55)
    }

    func testCountdownProgressNearEnd() {
        let start = Date().addingTimeInterval(-330)  // 5.5 min ago
        let end = Date().addingTimeInterval(30)     // 30 sec from now
        let state = MenuBarIconState(
            isActive: true,
            mode: .systemAndDisplay,
            activationStartTime: start,
            activeUntil: end
        )
        let progress = state.countdownProgress
        XCTAssertNotNil(progress)
        XCTAssertGreaterThan(progress!, 0.0)
        XCTAssertLessThan(progress!, 0.1)
    }

    func testCountdownProgressAfterExpiry() {
        let start = Date().addingTimeInterval(-7200)  // 2 hours ago
        let end = Date().addingTimeInterval(-60)      // 1 min ago (expired)
        let state = MenuBarIconState(
            isActive: true,
            mode: .systemOnly,
            activationStartTime: start,
            activeUntil: end
        )
        XCTAssertEqual(state.countdownProgress, 0.0)
    }

    // MARK: - Icon Image Tests

    func testIconImageInactive() {
        let image = MenuBarIcon.makeImage(
            isSystemActive: false,
            isDisplayActive: false,
            activeMode: nil
        )
        XCTAssertNotNil(image)
        XCTAssertEqual(image.size, MenuBarIcon.iconSize)
    }

    func testIconImageActive() {
        let image = MenuBarIcon.makeImage(
            isSystemActive: true,
            isDisplayActive: false,
            activeMode: .systemOnly
        )
        XCTAssertNotNil(image)
        XCTAssertEqual(image.size, MenuBarIcon.iconSize)
    }

    func testIconImageWithCountdown() {
        let start = Date()
        let end = start.addingTimeInterval(3600)
        let image = MenuBarIcon.makeImage(
            isSystemActive: true,
            isDisplayActive: true,
            activeMode: .systemAndDisplay,
            activationStartTime: start,
            activeUntil: end
        )
        XCTAssertNotNil(image)
        XCTAssertEqual(image.size, MenuBarIcon.iconSize)
    }

    func testIconImageStateEquatable() {
        let state1 = MenuBarIconState(
            isActive: true,
            mode: .systemOnly,
            activationStartTime: nil,
            activeUntil: nil
        )
        let state2 = MenuBarIconState(
            isActive: true,
            mode: .systemOnly,
            activationStartTime: nil,
            activeUntil: nil
        )
        XCTAssertEqual(state1, state2)

        let image1 = MenuBarIcon.makeImage(state: state1)
        let image2 = MenuBarIcon.makeImage(state: state2)
        XCTAssertEqual(image1.size, image2.size)
    }
}
