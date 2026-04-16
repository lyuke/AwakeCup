import XCTest
@testable import AwakeCup

final class AwakeCupTests: XCTestCase {
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
