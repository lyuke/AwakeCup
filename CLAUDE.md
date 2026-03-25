# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AwakeCup is a macOS menu bar application (like Caffeine) that prevents the system and/or display from going to sleep. It uses IOKit power management assertions to control sleep behavior and ServiceManagement for login item registration.

## Build Commands

- **Build**: `swift build`
- **Release build**: `swift build -c release`
- **Run directly**: `swift run`
- **Create distribution DMG**: `./Scripts/release_macos.sh`

## Architecture

The entire application is contained in a single Swift file at `Sources/AwakeCup/AwakeCup.swift`:

- **CaffeineManager** (`@MainActor`, `ObservableObject`): Manages IOKit power assertions for system and display sleep prevention. Uses `IOPMAssertionCreateWithName` / `IOPMAssertionRelease` APIs.

- **LaunchAtLogin** (`private enum`): Handles login item registration using `SMAppService` (macOS 13+) with LaunchAgent fallback for older systems.

- **AppDelegate**: Standard AppKit delegate that sets `NSApp.setActivationPolicy(.accessory)` for menu bar–only operation.

- **AwakeCupApp** (`@main`): SwiftUI app using `MenuBarExtra` for the menu bar interface.

## Key Implementation Details

- Uses `@AppStorage("launchAtLogin")` for persisting the login item preference
- `LSUIElement = true` in Info.plist hides the app from Dock (menu bar only)
- The menu bar icon toggles between `cup.and.saucer` and `cup.and.saucer.fill` based on active state
- Supports three modes: system + display, system only, display only
- Duration options: 5 minutes, 1 hour, 2 hours, or indefinite
