# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

AwakeCup is a macOS menu bar application (like Caffeine) that prevents the system and/or display from going to sleep. It uses IOKit power management assertions to control sleep behavior, ServiceManagement for login item registration, and Accessibility APIs for best-effort third-party menu bar item management.

## Build Commands

- **Build**: `swift build`
- **Release build**: `swift build -c release`
- **Run directly**: `swift run`
- **Create distribution DMG**: `./Scripts/release_macos.sh`

## Architecture

The core app shell and sleep-prevention behavior live in `Sources/AwakeCup/AwakeCup.swift`:

- **CaffeineManager** (`@MainActor`, `ObservableObject`): Manages IOKit power assertions for system and display sleep prevention. Uses `IOPMAssertionCreateWithName` / `IOPMAssertionRelease` APIs.

- **LaunchAtLogin** (`private enum`): Handles login item registration using `SMAppService` (macOS 13+) with LaunchAgent fallback for older systems.

- **TopMenuBarAutoHide**: Applies AppKit presentation options for the "auto-hide top menu bar" preference.

- **AppDelegate**: Standard AppKit delegate that sets `NSApp.setActivationPolicy(.accessory)` for menu bar–only operation.

- **AwakeCupApp** (`@main`): SwiftUI app using `MenuBarExtra` for the menu bar interface.

Menu bar item management is split across `Sources/AwakeCup/MenuBarManager/`:

- **AccessibilityPermissionController**: Checks and requests Accessibility trust.
- **MenuBarAXClient**: Reads third-party menu bar extras through `AXExtrasMenuBar`, presses AX menu bar items, and registers AX observers.
- **MenuBarInventoryService**: Refreshes, sorts, and observes the current menu bar item inventory.
- **MenuBarLayoutStore**: Persists hidden/always-visible assignments and ordering.
- **MenuBarPresentationController**: Tracks whether hidden items are shown as a panel or expanded strip.
- **MenuBarOverlayController**: Draws masks over hidden item positions and presents the expanded strip.
- **MenuBarManagerViewModel**: Coordinates permissions, inventory, layout, presentation, and overlay behavior.
- **MenuBarExtraContentView** and **MenuBarManagerSettingsView**: SwiftUI surfaces for quick controls and the settings window.

## Key Implementation Details

- Uses `@AppStorage("launchAtLogin")` for persisting the login item preference
- Uses `@AppStorage("autoHideTopMenuBar")` for persisting the top menu bar auto-hide preference
- `LSUIElement = true` in Info.plist hides the app from Dock (menu bar only)
- The menu bar icon is rendered as an `NSImage` with mode badges and optional countdown arc
- Supports three modes: system + display, system only, display only
- Duration options include custom minutes/hours, 1 hour, 2 hours, or indefinite
